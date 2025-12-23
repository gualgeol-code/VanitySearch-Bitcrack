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

# Base GENCODE flags common to most CUDA versions
GENCODE_BASE := -gencode=arch=compute_60,code=sm_60 \
                -gencode=arch=compute_61,code=sm_61 \
                -gencode=arch=compute_75,code=sm_75

# Conditional GENCODE flags based on CUDA version
# CUDA 11.0: support up to compute_80 (Volta)
# CUDA 11.1-11.7: support up to compute_86 (Ampere)
# CUDA 11.8+: support up to compute_89 (Ada Lovelace)

# Calculate CUDA version as integer (major * 100 + minor)
CUDA_VERSION_INT := $(shell expr $(CUDA_MAJOR) \* 100 + $(CUDA_MINOR))

ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1180), 1)
    # CUDA 11.8+ - full support up to compute_89
    $(info CUDA 11.8+ detected - full GPU architecture support)
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80 \
                     -gencode=arch=compute_86,code=sm_86 \
                     -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_89,code=compute_89
else ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1110), 1)
    # CUDA 11.1-11.7 - support up to compute_86
    $(info CUDA 11.1-11.7 detected - including Ampere (sm_86) support)
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80 \
                     -gencode=arch=compute_86,code=sm_86
else ifeq ($(shell expr $(CUDA_VERSION_INT) \>= 1100), 1)
    # CUDA 11.0 - support up to compute_80 ONLY
    $(warning CUDA 11.0 detected - limited to architectures up to Volta (sm_80))
    $(warning compute_86 (Ampere) and compute_89 (Ada) are NOT supported)
    GENCODE_EXTRA := -gencode=arch=compute_80,code=sm_80
else
    # CUDA 10.x or older
    $(warning CUDA $(CUDA_VERSION) detected - only basic GPU architectures enabled)
    $(warning Up to Turing (sm_75) architectures only)
    GENCODE_EXTRA :=
endif

# Combined GENCODE flags
GENCODE_FLAGS := $(GENCODE_BASE) $(GENCODE_EXTRA)

# Simplified GPU detection
GPU_DETECT := $(shell nvidia-smi -L 2>/dev/null | head -n1 || echo "Unknown GPU")
$(info GPU detected: $(GPU_DETECT))

# Check GPU architecture and warn if unsupported
ifneq ($(GPU_DETECT),Unknown GPU)
    ifeq ($(shell echo "$(GPU_DETECT)" | grep -i "RTX 40\|Ada\|4090\|4080" | wc -l), 1)
        ifneq ($(shell expr $(CUDA_VERSION_INT) \>= 1180), 1)
            $(error Ada Lovelace GPU detected but CUDA $(CUDA_VERSION) is too old. Requires CUDA 11.8+)
        endif
    else ifeq ($(shell echo "$(GPU_DETECT)" | grep -i "RTX 30\|Ampere\|3060\|3070\|3080\|3090" | wc -l), 1)
        ifneq ($(shell expr $(CUDA_VERSION_INT) \>= 1110), 1)
            $(warning Ampere GPU detected but CUDA $(CUDA_VERSION) is too old. Requires CUDA 11.1+ for full support)
        endif
    endif
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

# Build with minimal GPU support (for CUDA 11.0)
cuda11.0-compat:
	@echo "Building with CUDA 11.0 compatibility..."
	@make GENCODE_EXTRA="-gencode=arch=compute_80,code=sm_80"

# Manual override for specific architectures
build-with-arch:
	@echo "Available architecture presets:"
	@echo "  make pascal    # Pascal only (GTX 10 series)"
	@echo "  make turing    # Turing only (RTX 20 series)"
	@echo "  make volta     # Volta only (Tesla V100)"
	@echo "  make max-compat # Maximum compatibility for your CUDA $(CUDA_VERSION)"

# Architecture presets
pascal:
	@make GENCODE_FLAGS="-gencode=arch=compute_60,code=sm_60 -gencode=arch=compute_61,code=sm_61"

turing:
	@make GENCODE_FLAGS="-gencode=arch=compute_75,code=sm_75"

volta:
	@make GENCODE_FLAGS="-gencode=arch=compute_70,code=sm_70 -gencode=arch=compute_72,code=sm_72"

max-compat:
	@echo "Building with maximum compatibility for CUDA $(CUDA_VERSION)..."
	@if [ $(CUDA_VERSION_INT) -ge 1180 ]; then \
		make GENCODE_FLAGS="-gencode=arch=compute_60,code=sm_60 -gencode=arch=compute_61,code=sm_61 -gencode=arch=compute_75,code=sm_75 -gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 -gencode=arch=compute_89,code=sm_89"; \
	elif [ $(CUDA_VERSION_INT) -ge 1110 ]; then \
		make GENCODE_FLAGS="-gencode=arch=compute_60,code=sm_60 -gencode=arch=compute_61,code=sm_61 -gencode=arch=compute_75,code=sm_75 -gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86"; \
	elif [ $(CUDA_VERSION_INT) -ge 1100 ]; then \
		make GENCODE_FLAGS="-gencode=arch=compute_60,code=sm_60 -gencode=arch=compute_61,code=sm_61 -gencode=arch=compute_75,code=sm_75 -gencode=arch=compute_80,code=sm_80"; \
	else \
		make GENCODE_FLAGS="-gencode=arch=compute_60,code=sm_60 -gencode=arch=compute_61,code=sm_61 -gencode=arch=compute_75,code=sm_75"; \
	fi

# Update CUDA suggestion
update-cuda-suggestion:
	@echo ""
	@echo "=== CUDA Update Suggestion ==="
	@echo "Current CUDA version: $(CUDA_VERSION)"
	@if [ $(CUDA_VERSION_INT) -eq 1100 ]; then \
		echo "You have CUDA 11.0 which supports:"; \
		echo "  - Pascal (sm_60, sm_61)"; \
		echo "  - Turing (sm_75)"; \
		echo "  - Volta (sm_70, sm_72, sm_80)"; \
		echo ""; \
		echo "To support newer GPUs:"; \
		echo "  - CUDA 11.1+ for Ampere (RTX 30 series)"; \
		echo "  - CUDA 11.8+ for Ada Lovelace (RTX 40 series)"; \
	fi

# Utility targets
info:
	@echo "=== Build Information ==="
	@echo "CUDA Version: $(CUDA_VERSION) (Version code: $(CUDA_VERSION_INT))"
	@echo "GPU Info: $(GPU_DETECT)"
	@echo "CXX Compiler: $(CXX)"
	@echo "NVCC Compiler: $(NVCC)"
	@echo "GENCODE Flags:"
	@for flag in $(GENCODE_FLAGS); do \
		echo "  $$flag"; \
	done
	@echo ""
	@echo "Available architecture targets:"
	@echo "  make pascal       - Pascal GPUs (GTX 10 series)"
	@echo "  make turing       - Turing GPUs (RTX 20 series)"
	@echo "  make volta        - Volta GPUs (Tesla V100)"
	@echo "  make max-compat   - Maximum compatibility for CUDA $(CUDA_VERSION)"
	@echo "  make cuda11.0-compat - Explicit CUDA 11.0 compatibility"

# Help target
help:
	@echo "=== VanitySearch Makefile Help ==="
	@echo "Available targets:"
	@echo "  make all             - Build VanitySearch (default)"
	@echo "  make debug           - Build with debug symbols"
	@echo "  make clean           - Clean build files"
	@echo "  make info            - Show build configuration"
	@echo "  make help            - Show this help"
	@echo "  make cuda11.0-compat - Build for CUDA 11.0 compatibility"
	@echo "  make max-compat      - Build with max compatibility"
	@echo ""
	@echo "Architecture-specific targets:"
	@echo "  make pascal          - Pascal GPUs only"
	@echo "  make turing          - Turing GPUs only"
	@echo "  make volta           - Volta GPUs only"
	@echo ""
	@echo "Environment variables:"
	@echo "  debug=1              - Enable debug build"
	@echo ""
	@echo "Example:"
	@echo "  make debug=1         # Build with debugging enabled"
	@echo "  make clean all       # Clean and rebuild"
	@echo "  make cuda11.0-compat # Explicit CUDA 11.0 build"

.PHONY: all clean info help cuda11.0-compat build-with-arch pascal turing volta max-compat update-cuda-suggestion
