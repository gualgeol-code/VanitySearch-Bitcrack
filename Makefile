#!/bin/bash

echo "=== Building VanitySearch ==="
echo "CUDA: $(nvcc --version | grep release)"
echo "C++: $(g++-11 --version | head -1)"
echo ""

# Clean
rm -rf obj vanitysearch 2>/dev/null
mkdir -p obj/GPU obj/hash

# Compile CUDA
echo "Compiling CUDA code..."
nvcc -maxrregcount=0 --ptxas-options=-v --compile \
     --compiler-options -fPIC -ccbin /usr/bin/g++-11 -m64 \
     -O2 -I/usr/local/cuda/include \
     -gencode=arch=compute_60,code=sm_60 \
     -gencode=arch=compute_61,code=sm_61 \
     -gencode=arch=compute_75,code=sm_75 \
     -o obj/GPU/GPUEngine.o -c GPU/GPUEngine.cu

# Compile C++ files
echo "Compiling C++ files..."
for cpp in Base58 IntGroup main Random Timer Int IntMod Point SECP256K1 Vanity; do
    echo "  $cpp.cpp"
    g++-11 -mssse3 -Wno-write-strings -O2 -I. -I/usr/local/cuda/include \
           -o obj/$cpp.o -c $cpp.cpp
done

# Compile GPU C++ file
echo "  GPU/GPUGenerate.cpp"
g++-11 -mssse3 -Wno-write-strings -O2 -I. -I/usr/local/cuda/include \
       -o obj/GPU/GPUGenerate.o -c GPU/GPUGenerate.cpp

# Compile hash files
for hash in ripemd160 sha256 sha512 ripemd160_sse sha256_sse; do
    echo "  hash/$hash.cpp"
    g++-11 -mssse3 -Wno-write-strings -O2 -I. -I/usr/local/cuda/include \
           -o obj/hash/$hash.o -c hash/$hash.cpp
done

# Compile remaining files
echo "  Bech32.cpp"
g++-11 -mssse3 -Wno-write-strings -O2 -I. -I/usr/local/cuda/include \
       -o obj/Bech32.o -c Bech32.cpp

echo "  Wildcard.cpp"
g++-11 -mssse3 -Wno-write-strings -O2 -I. -I/usr/local/cuda/include \
       -o obj/Wildcard.o -c Wildcard.cpp

# Link
echo "Linking..."
g++-11 -o vanitysearch obj/*.o obj/GPU/*.o obj/hash/*.o \
       -lpthread -L/usr/local/cuda/lib64 -lcudart

# Check result
if [ -f "vanitysearch" ]; then
    echo ""
    echo "=== BUILD SUCCESSFUL ==="
    echo "File: ./vanitysearch"
    echo "Size: $(wc -c < vanitysearch) bytes"
    echo ""
    echo "Test run:"
    ./vanitysearch --help 2>/dev/null | head -20 || echo "Help not available"
else
    echo ""
    echo "=== BUILD FAILED ==="
    exit 1
fi
