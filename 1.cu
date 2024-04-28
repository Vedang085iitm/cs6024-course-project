#include <bits/stdc++.h>
#include <numeric>
#include <chrono>
#include <cuda_runtime.h>
#include <cuda.h>
#include <stdio.h>
#include <fstream>

using namespace std;

using std::cin;
using std::cout;


__global__ void rowsum(int *d_matrix, int *d_sums, int n)
{
    long block_Idx = blockIdx.x + (gridDim.x) * blockIdx.y + (gridDim.y * gridDim.x) * blockIdx.z;
    long thread_Idx = threadIdx.x + (blockDim.x) * threadIdx.y + (blockDim.y * blockDim.x) * threadIdx.z;
    long block_Capacity = blockDim.x * blockDim.y * blockDim.z;
    long i = block_Idx * block_Capacity + thread_Idx;

    if (i < n)
    {
        d_sums[i] = 0; // Initialize the sum to 0
        for (int j = 0; j < n; ++j)
        {
            atomicAdd(&d_sums[i], d_matrix[i * n + j]);
        }
    }
}

__global__ void neighborJoiningMatrix(int *d_matrix, int *d_rowSums, int *d_njMatrix, int n)
{
    long block_Idx = blockIdx.x + (gridDim.x) * blockIdx.y + (gridDim.y * gridDim.x) * blockIdx.z;
    long thread_Idx = threadIdx.x + (blockDim.x) * threadIdx.y + (blockDim.y * blockDim.x) * threadIdx.z;
    long block_Capacity = blockDim.x * blockDim.y * blockDim.z;
    long arr_Idx = block_Idx * block_Capacity + thread_Idx;

    if (arr_Idx < n * n)
    {
        int i = arr_Idx / n;
        int j = arr_Idx % n;

        if (i == j)
        {
            d_njMatrix[arr_Idx] = 0;
        }
        else
        {
            d_njMatrix[arr_Idx] = (n - 2) * d_matrix[arr_Idx] - d_rowSums[i] - d_rowSums[j];
        }
    }
}

__global__ void findMinIndices(int *d_njMatrix, int *d_rowSums, int *d_minVal, int *d_minIndexI, int *d_minIndexJ, int *d_delta, int n)
{
    extern __shared__ int sharedData[];
    extern __shared__ int sharedIndices[];

    long block_Idx = blockIdx.x + (gridDim.x) * blockIdx.y + (gridDim.y * gridDim.x) * blockIdx.z;
    long thread_Idx = threadIdx.x + (blockDim.x) * threadIdx.y + (blockDim.y * blockDim.x) * threadIdx.z;
    long block_Capacity = blockDim.x * blockDim.y * blockDim.z;
    long arr_Idx = block_Idx * block_Capacity + thread_Idx;

    int i = arr_Idx / n;
    int j = arr_Idx % n;

    if (i < n && j < n && i != j)
    {
        sharedData[thread_Idx] = d_njMatrix[arr_Idx];
        sharedIndices[thread_Idx] = arr_Idx;
    }
    else
    {
        sharedData[thread_Idx] = INT_MAX;
    }

    __syncthreads();

    for (unsigned int s = blockDim.x / 2; s > 0; s >>= 1)
    {
        if (thread_Idx < s)
        {
            if (sharedData[thread_Idx] > sharedData[thread_Idx + s])
            {
                sharedData[thread_Idx] = sharedData[thread_Idx + s];
                sharedIndices[thread_Idx] = sharedIndices[thread_Idx + s];
            }
        }
        __syncthreads();
    }
  
    if (thread_Idx == 0)
    {
        *d_minVal = sharedData[0];
     
        *d_minIndexI = sharedIndices[0] / n;
        *d_minIndexJ = sharedIndices[0] % n;
        *d_delta = (d_rowSums[*d_minIndexI] - d_rowSums[*d_minIndexJ]) / (n - 2);
    }
 
__syncthreads();

}

int main(int argc, char **argv)
{

    int n;
    // cout << "Enter the size of the matrix: " << endl;
    cin >> n;
    // cout << "Enter the matrix: " << endl;
    int *matrix = new int[n * n];
    for (int i = 0; i < n; ++i)
    {
        for (int j = 0; j < n; ++j)
        {
            cin >> matrix[i * n + j];
        }
    }

    ofstream outfile("cuda.out");
    
    int *sums = new int[n];
    int *d_matrix;
    int *d_sums;
    cudaMalloc(&d_matrix, n * n * sizeof(int));
    cudaMalloc(&d_sums, n * sizeof(int));
    cudaMemcpy(d_matrix, matrix, n * n * sizeof(int), cudaMemcpyHostToDevice);

    dim3 blockSize(512);
    dim3 numBlocks((n + blockSize.x - 1) / blockSize.x);

    auto start = std::chrono::high_resolution_clock::now();
    rowsum<<<numBlocks, blockSize>>>(d_matrix, d_sums, n);
    cudaDeviceSynchronize();
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed1 = end - start;
    // cast it to microseconds
auto elapsed1_casted = std::chrono::duration_cast<std::chrono::microseconds>(elapsed1).count();

     

    outfile << "Row sums: " << endl;
    cudaMemcpy(sums, d_sums, n * sizeof(int), cudaMemcpyDeviceToHost);
    for (int i = 0; i < n; ++i)
    {
        outfile << sums[i] << " ";
    }
    outfile << endl;

    int *njMatrix = new int[n * n];
    int *d_njMatrix;
    cudaMalloc(&d_njMatrix, n * n * sizeof(int));
     start = std::chrono::high_resolution_clock::now();
    neighborJoiningMatrix<<<numBlocks, blockSize>>>(d_matrix, d_sums, d_njMatrix, n);
    cudaDeviceSynchronize();
     end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed2 = end - start;
  auto elapsed2_casted = std::chrono::duration_cast<std::chrono::microseconds>(elapsed2).count();


    cudaMemcpy(njMatrix, d_njMatrix, n * n * sizeof(int), cudaMemcpyDeviceToHost);
    outfile << "Neighbor joining matrix: " << endl;
    for (int i = 0; i < n; ++i)
    {
        for (int j = 0; j < n; ++j)
        {
            outfile << njMatrix[i * n + j] << " ";
        }
        outfile << endl;
    }

    int *d_minVal, *d_minIndexI, *d_minIndexJ, *d_delta;
    cudaMalloc(&d_minVal, sizeof(int));
    cudaMalloc(&d_minIndexI, sizeof(int));
    cudaMalloc(&d_minIndexJ, sizeof(int));
    cudaMalloc(&d_delta, sizeof(int));
    cudaMemcpy(d_minVal, new int, sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_minIndexI, new int, sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_minIndexJ, new int, sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_delta, new int, sizeof(int), cudaMemcpyHostToDevice);

    // shared memory
    int sharedMemSize = blockSize.x * sizeof(int);
     start = std::chrono::high_resolution_clock::now();
    findMinIndices<<<numBlocks, blockSize, sharedMemSize>>>(d_njMatrix, d_sums, d_minVal, d_minIndexI, d_minIndexJ, d_delta, n);
    cudaDeviceSynchronize();
     end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed3 = end - start;
 auto elapsed3_casted = std::chrono::duration_cast<std::chrono::microseconds>(elapsed3).count();


    // print the deltas
    int delta;

    cudaMemcpy(&delta, d_delta, sizeof(int), cudaMemcpyDeviceToHost);
    outfile << "Delta: " << delta << endl;

    

    //print the timings in another file
   std::ofstream file2("cuda_timing.out");
if(file2.is_open()) {
    //print the casted values
    file2 <<"For rowsum: " <<elapsed1_casted << " Microseconds"<<"\n";
    file2 <<"For NEIGHBORJOINING matrix: "<< elapsed2_casted << " Microseconds" <<"\n";
    file2 << "For MinIndices: "<<elapsed3_casted << "Microseconds"<<"\n";
    file2.close();
} else {
    std::cout << "Unable to open file";
}

    delete[] matrix;
    delete[] sums;
    cudaFree(d_matrix);
    cudaFree(d_sums);
    cudaFree(d_njMatrix);
    outfile.close();

    return 0;
}
