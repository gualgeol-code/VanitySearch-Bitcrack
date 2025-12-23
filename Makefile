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
# compute_86 requires CUDA 11.0+
# compute_89 requires CUDA 11.1+
ifeq ($(shell expr $(CUDA_MAJOR) \>= 11), 1)
    # CUDA 11.x or newer
    GENCODE_EXTRA := -gencode=arch=compute_86,code=sm_86 \
                     -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_89,code=compute_89
    $(info Using CUDA 11+ compatible GPU architectures including Ampere (sm_86))
else
    # CUDA 10.x or older
    GENCODE_EXTRA := -gencode=arch=compute_89,code=sm_89 \
                     -gencode=arch=compute_89,code=compute_89
    $(warning CUDA $(CUDA_VERSION) detected - sm_86 (Ampere/RTX 30 series) disabled)
    $(info Using CUDA 10 compatible GPU architectures (Pascal, Volta, Turing))
endif

# Combined GENCODE flags
GENCODE_FLAGS := $(GENCODE_BASE) $(GENCODE_EXTRA)

# Auto-detect GPU and suggest optimal architecture
GPU_INFO := $(shell nvidia-smi --query-gpu=name,compute_capability --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ' || echo "Unknown GPU")
$(info GPU detected: $(GPU_INFO))

# Optimize for specific GPU if detected
ifneq ($(GPU_INFO),Unknown GPU)
    GPU_CC := $(shell echo $(GPU_INFO) | grep -o ",[0-9.]*" | cut -d, -f2)
    ifneq ($(GPU_CC),)
        $(info GPU Compute Capability: $(GPU_CC))
        # You could add optimization based on specific GPU here
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
	@echo "Build complete. CUDA $(CUDA_VERSION) with GPU arch:"
	@echo "  $(GENCODE_FLAGS)"

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

# Utility targets
info:
	@echo "=== Build Information ==="
	@echo "CUDA Version: $(CUDA_VERSION)"
	@echo "CUDA Major: $(CUDA_MAJOR)"
	@echo "GPU Info: $(GPU_INFO)"
	@echo "CXX Compiler: $(CXX)"
	@echo "NVCC Compiler: $(NVCC)"
	@echo "GENCODE Flags:"
	@echo "  $(GENCODE_FLAGS)"

# Help target
help:
	@echo "=== VanitySearch Makefile Help ==="
	@echo "Available targets:"
	@echo "  make all           - Build VanitySearch (default)"
	@echo "  make debug         - Build with debug symbols"
	@echo "  make clean         - Clean build files"
	@echo "  make info          - Show build configuration"
	@echo "  make help          - Show this help"
	@echo ""
	@echo "Environment variables:"
	@echo "  debug=1            - Enable debug build"
	@echo ""
	@echo "Example:"
	@echo "  make debug=1       # Build with debugging enabled"
	@echo "  make clean all     # Clean and rebuild"

.PHONY: all clean info help
