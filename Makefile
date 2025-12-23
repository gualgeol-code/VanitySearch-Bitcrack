#---------------------------------------------------------------------
# Makefile for vanitysearch
#
# Author : Jean-Luc PONS
# Modified: Added CUDA version auto-detection and GPU arch compatibility

SRC = Base58.cpp IntGroup.cpp main.cpp Random.cpp \
      Timer.cpp Int.cpp IntMod.cpp Point.cpp SECP256K1.cpp \
      Vanity.cpp GPU/GPUGenerate.cpp hash/ripemd160.cpp \
      hash/sha256.cpp hash/sha512.cpp hash/ripemd160_sse.cpp \
      hash/sha256_sse.cpp Bech32.cpp Wildcard.cpp

OBJDIR = obj

OBJET = $(addprefix $(OBJDIR)/, \
        Base58.o IntGroup.o main.o Random.o Timer.o Int.o \
        IntMod.o Point.o SECP256K1.o Vanity.o GPU/GPUGenerate.o \
        hash/ripemd160.o hash/sha256.o hash/sha512.o \
        hash/ripemd160_sse.o hash/sha256_sse.o \
        GPU/GPUEngine.o Bech32.o Wildcard.o)

CXX        = g++-9
CUDA       = /usr/local/cuda
CXXCUDA    = /usr/bin/g++-9
NVCC       = $(CUDA)/bin/nvcc

# Auto-detect CUDA version
CUDA_VERSION := $(shell $(NVCC) --version | grep -o "release [0-9]*\.[0-9]*" | cut -d' ' -f2 2>/dev/null || echo "0.0")
CUDA_MAJOR := $(shell echo $(CUDA_VERSION) | cut -d. -f1)
CUDA_MINOR := $(shell echo $(CUDA_VERSION) | cut -d. -f2)

# Debug info
$(info Detected CUDA version: $(CUDA_VERSION))

# Base GENCODE flags common to all CUDA versions
GENCODE_BASE := -gencode=arch=compute_60,code=sm_60 \
                -gencode=arch=compute_61,code=sm_61 \
                -gencode=arch=compute_75,code=sm_75 \
                -gencode=arch=compute_80,code=sm_80

# Conditional GENCODE flags based on CUDA version
# compute_86 (Ampere) requires CUDA 11.1+
# compute_89 (Ada Lovelace) requires CUDA 11.8+
ifeq ($(shell expr $(CUDA_MAJOR) \>= 12), 1)
    # CUDA 12.x - full support
    $(info CUDA 12.x detected - full GPU architecture support)
    GENCODE_EXTRA := -gencode=arch=compute_86,code=sm_86 \
                     -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_89,code=compute_89
else ifeq ($(shell expr $(CUDA_MAJOR) \>= 11), 1)
    # CUDA 11.x
    ifeq ($(shell expr $(CUDA_MINOR) \>= 1), 1)
        # CUDA 11.1+ supports compute_86
        $(info CUDA 11.1+ detected - including Ampere (sm_86) support)
        GENCODE_EXTRA := -gencode=arch=compute_86,code=sm_86 \
                         -gencode=arch=compute_89,code=sm_89 \
                         -gencode=arch=compute_89,code=compute_89
    else ifeq ($(shell expr $(CUDA_MINOR) \>= 0), 1)
        # CUDA 11.0 does NOT support compute_86
        $(warning CUDA 11.0 detected - sm_86 (Ampere/RTX 30 series) disabled)
        $(warning Upgrade to CUDA 11.1+ for Ampere GPU support)
        GENCODE_EXTRA := -gencode=arch=compute_89,code=sm_89 \
                         -gencode=arch=compute_89,code=compute_89
    endif
else
    # CUDA 10.x or older
    $(warning CUDA $(CUDA_VERSION) detected - only basic GPU architectures enabled)
    GENCODE_EXTRA := -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_89,code=compute_89
endif

# Combined GENCODE flags
GENCODE_FLAGS := $(GENCODE_BASE) $(GENCODE_EXTRA)

# Simplified GPU detection
GPU_DETECT := $(shell nvidia-smi -L 2>/dev/null | head -n1 || echo "Unknown GPU")
$(info GPU detected: $(GPU_DETECT))

# Check if we have an Ampere GPU (RTX 30 series)
ifeq ($(shell echo "$(GPU_DETECT)" | grep -i "RTX 30\|RTX A\|A100\|A10\|A2\|Ampere" | wc -l), 1)
    $(warning Ampere GPU detected but CUDA $(CUDA_VERSION) may not fully support it)
    $(warning Consider upgrading to CUDA 11.1+ for optimal performance)
endif

ifdef debug
CXXFLAGS   = -mssse3 -Wno-write-strings -g -I. -I$(CUDA)/include
NVCC_DEBUG = -G -g
else
CXXFLAGS   = -mssse3 -Wno-write-strings -O2 -I. -I$(CUDA)/include
NVCC_DEBUG = -O2
endif

LFLAGS     = -lpthread -L$(CUDA)/lib64 -lcudart

#--------------------------------------------------------------------

# Unified GPU compilation rule with auto-detected GENCODE flags
$(OBJDIR)/GPU/GPUEngine.o: GPU/GPUEngine.cu
	@echo "Compiling GPU code with CUDA $(CUDA_VERSION)..."
	@echo "Using GPU architectures:"
	@echo "  $(GENCODE_FLAGS)"
	$(NVCC) -maxrregcount=0 --ptxas-options=-v --compile \
	        --compiler-options -fPIC -ccbin $(CXXCUDA) -m64 \
	        $(NVCC_DEBUG) -I$(CUDA)/include \
	        $(GENCODE_FLAGS) \
	        -o $(OBJDIR)/GPU/GPUEngine.o -c GPU/GPUEngine.cu

$(OBJDIR)/%.o : %.cpp
	$(CXX) $(CXXFLAGS) -o $@ -c $<

all: VanitySearch

VanitySearch: $(OBJET)
	@echo "Linking VanitySearch..."
	$(CXX) $(OBJET) $(LFLAGS) -o vanitysearch
	@echo "Build complete with CUDA $(CUDA_VERSION)"

$(OBJET): | $(OBJDIR) $(OBJDIR)/GPU $(OBJDIR)/hash

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(OBJDIR)/GPU: $(OBJDIR)
	cd $(OBJDIR) && mkdir -p GPU

$(OBJDIR)/hash: $(OBJDIR)
	cd $(OBJDIR) && mkdir -p hash

clean:
	@echo "Cleaning build files..."
	@rm -f obj/*.o
	@rm -f obj/GPU/*.o
	@rm -f obj/hash/*.o

# Quick fix for CUDA 11.0: disable compute_86
force-no-sm86:
	@echo "Forcing build without compute_86 (for CUDA 11.0)..."
	@make GENCODE_EXTRA="-gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_89,code=compute_89"

# Update CUDA suggestion
update-cuda-suggestion:
	@echo ""
	@echo "=== CUDA Update Suggestion ==="
	@echo "Current CUDA version: $(CUDA_VERSION)"
	@if [ $(CUDA_MAJOR) -eq 11 -a $(CUDA_MINOR) -eq 0 ]; then \
		echo "You have CUDA 11.0 which doesn't support Ampere GPUs (RTX 30 series)."; \
		echo "Recommended: Upgrade to CUDA 11.8 or 12.x"; \
		echo ""; \
		echo "Quick fix for now:"; \
		echo "  make force-no-sm86"; \
	fi

# Utility targets
info:
	@echo "=== Build Information ==="
	@echo "CUDA Version: $(CUDA_VERSION) (Major: $(CUDA_MAJOR), Minor: $(CUDA_MINOR))"
	@echo "GPU Info: $(GPU_DETECT)"
	@echo "CXX Compiler: $(CXX)"
	@echo "NVCC Compiler: $(NVCC)"
	@echo "GENCODE Flags:"
	@for flag in $(GENCODE_FLAGS); do \
		echo "  $$flag"; \
	done
	@echo ""
	@if [ $(CUDA_MAJOR) -eq 11 -a $(CUDA_MINOR) -eq 0 ]; then \
		echo "NOTE: CUDA 11.0 detected - compute_86 is disabled"; \
		echo "      Run 'make update-cuda-suggestion' for more info"; \
	fi

# Help target
help:
	@echo "=== VanitySearch Makefile Help ==="
	@echo "Available targets:"
	@echo "  make all           - Build VanitySearch (default)"
	@echo "  make debug         - Build with debug symbols"
	@echo "  make clean         - Clean build files"
	@echo "  make info          - Show build configuration"
	@echo "  make help          - Show this help"
	@echo "  make force-no-sm86 - Force build without compute_86"
	@echo ""
	@echo "Environment variables:"
	@echo "  debug=1            - Enable debug build"
	@echo ""
	@echo "Example:"
	@echo "  make debug=1       # Build with debugging enabled"
	@echo "  make clean all     # Clean and rebuild"

.PHONY: all clean info help force-no-sm86 update-cuda-suggestion
