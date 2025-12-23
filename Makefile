# Makefile for vanitysearch - Fixed Indentation
SRC = Base58.cpp IntGroup.cpp main.cpp Random.cpp \
      Timer.cpp Int.cpp IntMod.cpp Point.cpp SECP256K1.cpp \
      Vanity.cpp GPU/GPUGenerate.cpp hash/ripemd160.cpp \
      hash/sha256.cpp hash/sha512.cpp hash/ripemd160_sse.cpp \
      hash/sha256_sse.cpp Bech32.cpp Wildcard.cpp

OBJDIR = obj

OBJET = $(OBJDIR)/Base58.o $(OBJDIR)/IntGroup.o $(OBJDIR)/main.o \
        $(OBJDIR)/Random.o $(OBJDIR)/Timer.o $(OBJDIR)/Int.o \
        $(OBJDIR)/IntMod.o $(OBJDIR)/Point.o $(OBJDIR)/SECP256K1.o \
        $(OBJDIR)/Vanity.o $(OBJDIR)/GPU/GPUGenerate.o \
        $(OBJDIR)/hash/ripemd160.o $(OBJDIR)/hash/sha256.o \
        $(OBJDIR)/hash/sha512.o $(OBJDIR)/hash/ripemd160_sse.o \
        $(OBJDIR)/hash/sha256_sse.o $(OBJDIR)/GPU/GPUEngine.o \
        $(OBJDIR)/Bech32.o $(OBJDIR)/Wildcard.o

CXX        = g++-9
CUDA       = /usr/local/cuda
CXXCUDA    = /usr/bin/g++-9
NVCC       = $(CUDA)/bin/nvcc

CXXFLAGS   = -mssse3 -Wno-write-strings -O2 -I. -I$(CUDA)/include
LFLAGS     = -lpthread -L$(CUDA)/lib64 -lcudart

all: VanitySearch

VanitySearch: $(OBJET)
	@echo Making VanitySearch...
	$(CXX) $(OBJET) $(LFLAGS) -o vanitysearch

$(OBJDIR)/GPU/GPUEngine.o: GPU/GPUEngine.cu
	@mkdir -p $(OBJDIR)/GPU
	$(NVCC) -maxrregcount=0 --ptxas-options=-v --compile --compiler-options -fPIC -ccbin $(CXXCUDA) -m64 -O2 -I$(CUDA)/include -gencode=arch=compute_75,code=sm_75 -o $(OBJDIR)/GPU/GPUEngine.o -c GPU/GPUEngine.cu

$(OBJDIR)/%.o : %.cpp
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -o $@ -c $<

clean:
	@echo Cleaning...
	@rm -rf $(OBJDIR)
	@rm -f vanitysearch
