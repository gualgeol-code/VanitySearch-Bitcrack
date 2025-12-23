#---------------------------------------------------------------------
# Makefile for vanitysearch - Optimized for Google Colab (Tesla T4)
# Author : Jean-Luc PONS
#---------------------------------------------------------------------

SRC = Base58.cpp IntGroup.cpp main.cpp Random.cpp \
      Timer.cpp Int.cpp IntMod.cpp Point.cpp SECP256K1.cpp \
      Vanity.cpp GPU/GPUGenerate.cpp hash/ripemd160.cpp \
      hash/sha256.cpp hash/sha512.cpp hash/ripemd160_sse.cpp \
      hash/sha256_sse.cpp Bech32.cpp Wildcard.cpp [cite: 1]

OBJDIR = obj [cite: 1]

# Daftar file objek yang akan dihasilkan
OBJET = $(addprefix $(OBJDIR)/, \
        Base58.o IntGroup.o main.o Random.o Timer.o Int.o \
        IntMod.o Point.o SECP256K1.o Vanity.o GPU/GPUGenerate.o \
        hash/ripemd160.o hash/sha256.o hash/sha512.o \
        hash/ripemd160_sse.o hash/sha256_sse.o \
        GPU/GPUEngine.o Bech32.o Wildcard.o) [cite: 1, 2]

# Konfigurasi Compiler
CXX        = g++-9 [cite: 2]
CUDA       = /usr/local/cuda [cite: 2]
CXXCUDA    = /usr/bin/g++-9 [cite: 2]
NVCC       = $(CUDA)/bin/nvcc [cite: 2]

# Flag Kompilasi
ifdef debug
CXXFLAGS   = -mssse3 -Wno-write-strings -g -I. -I$(CUDA)/include [cite: 2, 3]
else
CXXFLAGS   = -mssse3 -Wno-write-strings -O2 -I. -I$(CUDA)/include 
endif
LFLAGS     = -lpthread -L$(CUDA)/lib64 -lcudart 

#--------------------------------------------------------------------
# Aturan Kompilasi Utama
#--------------------------------------------------------------------

all: VanitySearch

# Linker: Membuat file eksekusi akhir
VanitySearch: $(OBJET)
	@echo Making VanitySearch...
	$(CXX) $(OBJET) $(LFLAGS) -o vanitysearch 

# Kompilasi khusus untuk GPU Tesla T4 (sm_75)
$(OBJDIR)/GPU/GPUEngine.o: GPU/GPUEngine.cu
	$(NVCC) -maxrregcount=0 --ptxas-options=-v --compile --compiler-options -fPIC -ccbin $(CXXCUDA) -m64 -O2 -I$(CUDA)/include -gencode=arch=compute_75,code=sm_75 -o $(OBJDIR)/GPU/GPUEngine.o -c GPU/GPUEngine.cu 

# Kompilasi file .cpp menjadi file .o
$(OBJDIR)/%.o : %.cpp
	$(CXX) $(CXXFLAGS) -o $@ -c $< 

# Membuat struktur folder objek 
$(OBJET): | $(OBJDIR) $(OBJDIR)/GPU $(OBJDIR)/hash

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(OBJDIR)/GPU: $(OBJDIR)
	mkdir -p $(OBJDIR)/GPU

$(OBJDIR)/hash: $(OBJDIR)
	mkdir -p $(OBJDIR)/hash

clean:
	@echo Cleaning...
	@rm -rf $(OBJDIR)
	@rm -f vanitysearch
