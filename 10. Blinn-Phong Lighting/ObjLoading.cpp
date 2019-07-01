#include "ObjLoading.h"

#include <fcntl.h> //open()
#include <unistd.h> //close()
#include <sys/stat.h> //struct stat
#include <sys/mman.h> //mmap()

#include <assert.h>
#include <math.h> //pow(), fabs(), sqrtf()
#include <stdio.h>

// Based on the .obj loading code by Arseny Kapoulkine
// in the meshoptimizer project

static int parseInt(const char* s, const char** end)
{
    // skip whitespace
    while (*s == ' ' || *s == '\t')
        ++s;

    // read sign bit
    int sign = (*s == '-');
    if(*s == '-' || *s == '+') 
        ++s;

    unsigned int result = 0;
    while((unsigned(*s - '0') < 10))
    {
        result = result * 10 + (*s - '0');
        ++s;
    }

    // return end-of-string
    *end = s;

    return sign ? -int(result) : int(result);
}

static float parseFloat(const char* s, const char** end)
{
    static const double powers[] = {1e0, 1e+1, 1e+2, 1e+3, 1e+4, 1e+5, 1e+6, 1e+7, 1e+8, 1e+9, 1e+10, 1e+11, 1e+12, 1e+13, 1e+14, 1e+15, 1e+16, 1e+17, 1e+18, 1e+19, 1e+20, 1e+21, 1e+22};

    // skip whitespace
    while (*s == ' ' || *s == '\t')
        ++s;

    // read sign
    double sign = (*s == '-') ? -1 : 1;
    if(*s == '-' || *s == '+') 
        ++s;

    // read integer part
    double result = 0;
    int power = 0;

    while (unsigned(*s - '0') < 10)
    {
        result = result * 10 + (double)(*s - '0');
        ++s;
    }

    // read fractional part
    if (*s == '.')
    {
        ++s;

        while (unsigned(*s - '0') < 10)
        {
            result = result * 10 + (double)(*s - '0');
            ++s;
            --power;
        }
    }

    // read exponent part
    // NOTE: bitwise OR with ' ' will transform an uppercase char 
    // to lowercase while leaving lowercase chars unchanged
    if ((*s | ' ') == 'e')
    {
        ++s;

        // read exponent sign
        int expSign = (*s == '-') ? -1 : 1;
        if(*s == '-' || *s == '+') 
            ++s;

        // read exponent
        int expPower = 0;
        while (unsigned(*s - '0') < 10)
        {
            expPower = expPower * 10 + (*s - '0');
            ++s;
        }

        power += expSign * expPower;
    }

    // return end-of-string
    *end = s;

    // note: this is precise if result < 9e15
    // for longer inputs we lose a bit of precision here
    if (unsigned(-power) < sizeof(powers) / sizeof(powers[0]))
        return float(sign * result / powers[-power]);
    else if (unsigned(power) < sizeof(powers) / sizeof(powers[0]))
        return float(sign * result * powers[power]);
    else
        return float(sign * result * pow(10.0, power));
}

static const char* parseFaceElement(const char* s, int& vi, int& vti, int& vni)
{
    while (*s == ' ' || *s == '\t')
        ++s;

    vi = parseInt(s, &s);

    if (*s != '/')
        return s;
    ++s;

    // handle vi//vni indices
    if (*s != '/')
        vti = parseInt(s, &s);

    if (*s != '/')
        return s;
    ++s;

    vni = parseInt(s, &s);

    return s;
}

static int fixupIndex(int index, size_t size)
{
    return (index >= 0) ? index - 1 : int(size) + index;
}

static bool areAlmostEqual(float a, float b)
{
    return (fabs(a-b) < 0.00001f);
}

static void growArray(void** array, size_t* capacity, size_t itemSize)
{
    *capacity = (*capacity == 0) ? 32 : (*capacity + *capacity / 2);
    *array = realloc(*array, *capacity * itemSize);
    assert(*array);
}

LoadedObj loadObj(const char* filename)
{
    LoadedObj result = {};

    int file = open(filename, O_RDONLY);
    if (file < 0)
        return result;
    
    struct stat fs;
    fstat(file, &fs);

    uint32_t fileNumBytes = fs.st_size;

    const char* fileBytes = (const char*)mmap(0, fileNumBytes, PROT_READ, MAP_PRIVATE, file, 0);
    
    if (fileBytes == (void*)-1)
        return result;

    uint32_t numVertexvpItions = 0;
    uint32_t numVertexTexCoords = 0;
    uint32_t numVertexNormals = 0;
    uint32_t numFaces = 0;

    const char* s = fileBytes;
    while(s < fileBytes + fileNumBytes)
    {
        if(*s == 'v'){
            ++s;
            if(*s == ' ') ++numVertexvpItions;
            else if(*s == 't') ++numVertexTexCoords;
            else if(*s == 'n') ++numVertexNormals;
        }
        else if(*s == 'f') ++numFaces;

        while(*s != 0 && *s++ != '\n');
    }

    float* vpBuffer = (float*)malloc(numVertexvpItions * 3 * sizeof(float));
    float* vtBuffer = (float*)malloc(numVertexTexCoords * 2 * sizeof(float));
    float* vnBuffer = (float*)malloc(numVertexNormals * 3 * sizeof(float));
    float* vpIt = vpBuffer;
    float* vtIt = vtBuffer;
    float* vnIt = vnBuffer;

    size_t vertexBufferCapacity = 0;
    size_t indexBufferCapacity = 0;
    size_t vertexBufferSize = 0;
    size_t indexBufferSize = 0;
    VertexData* outVertexBuffer = NULL;
    uint16_t* outIndexBuffer = NULL;

    bool smoothNormals = false;

    s = fileBytes;
    while(s < fileBytes + fileNumBytes)
    {
        char currChar = *s;
        if(currChar == 'v'){
            ++s;
            currChar = *s++;
            if(currChar == ' '){
                *vpIt++ = parseFloat(s, &s);
                *vpIt++ = parseFloat(s, &s);
                *vpIt++ = parseFloat(s, &s);
            }
            else if(currChar == 't'){
                *vtIt++ = parseFloat(s, &s);
                *vtIt++ = parseFloat(s, &s);
            }
            else if(currChar == 'n'){
                *vnIt++ = parseFloat(s, &s);
                *vnIt++ = parseFloat(s, &s);
                *vnIt++ = parseFloat(s, &s);
            }
        }
        else if(currChar == 'f')
        {
            ++s;
            while(*s != '\n')
            {
                int vpIdx = 0, vtIdx = 0, vnIdx = 0;
                s = parseFaceElement(s, vpIdx, vtIdx, vnIdx);
                assert(vpIdx != 0);

                vpIdx = fixupIndex(vpIdx, numVertexvpItions);
                vtIdx = fixupIndex(vtIdx, numVertexTexCoords);
                vnIdx = fixupIndex(vnIdx, numVertexNormals);
                
                VertexData newVert = {
                    vpBuffer[3*vpIdx], vpBuffer[3*vpIdx+1], vpBuffer[3*vpIdx+2],
                    vtBuffer[2*vtIdx], vtBuffer[2*vtIdx+1],
                    vnBuffer[3*vnIdx], vnBuffer[3*vnIdx+1], vnBuffer[3*vnIdx+2],
                };

                // Search vertexBuffer for matching vertex
                int index;
                for(index=0; index<vertexBufferSize; ++index) 
                {
                    VertexData* v = outVertexBuffer + index;
                    bool posMatch = areAlmostEqual(v->pos[0], newVert.pos[0])
                                 && areAlmostEqual(v->pos[1], newVert.pos[1])
                                 && areAlmostEqual(v->pos[2], newVert.pos[2]);
                    bool uvMatch = areAlmostEqual(v->uv[0], newVert.uv[0])
                                && areAlmostEqual(v->uv[1], newVert.uv[1]);
                    bool normMatch = areAlmostEqual(v->norm[0], newVert.norm[0])
                                  && areAlmostEqual(v->norm[1], newVert.norm[1])
                                  && areAlmostEqual(v->norm[2], newVert.norm[2]);
                    if(posMatch && uvMatch)
                    {
                        if(normMatch || smoothNormals){
                            v->norm[0] += newVert.norm[0];
                            v->norm[1] += newVert.norm[1];
                            v->norm[2] += newVert.norm[2];
                            break;
                        }
                    }
                }
                if(index == vertexBufferSize){
                    if(vertexBufferSize + 1 > vertexBufferCapacity){
                        growArray((void**)(&outVertexBuffer), &vertexBufferCapacity, sizeof(VertexData));
                    }
                    outVertexBuffer[vertexBufferSize++] = newVert;
                }
                if(indexBufferSize + 1 > indexBufferCapacity){
                        growArray((void**)(&outIndexBuffer), &indexBufferCapacity, sizeof(uint16_t));
                }
                outIndexBuffer[indexBufferSize++] = index;
            }
        }
        else if(currChar == 's' && *(++s) == ' ')
        {
            ++s;
            if((*s == 'o' && *(s+1) == 'f' && *(s+2) == 'f') || *s == '0')
                smoothNormals = false;
            else {
                assert((*s == 'o' && *(s+1) == 'n') || (*s >= '1'&& *s <= '9'));
                smoothNormals = true;
            }
        }
        
        while(*s != 0 && *s++ != '\n');
    }

    // Normalise the normals
    for(int i=0; i<vertexBufferSize; ++i){
        VertexData* v = outVertexBuffer + i;
        float normLength = sqrtf(v->norm[0]*v->norm[0] 
                         + v->norm[1]*v->norm[1]
                         + v->norm[2]*v->norm[2]);
        float invNormLength = 1.f / normLength;
        v->norm[0] *= invNormLength;
        v->norm[1] *= invNormLength;
        v->norm[2] *= invNormLength;

        // printf("(%f, %f, %f) (%f, %f) (%f, %f, %f)\n",
        //     v->pos[0], v->pos[1], v->pos[2],
        //     v->uv[0], v->uv[1],
        //     v->norm[0], v->norm[1], v->norm[2]);
    }

    free(vpBuffer);
    free(vtBuffer);
    free(vnBuffer);
    munmap((void*)fileBytes, fileNumBytes);
    close(file);

    result.numVertices = vertexBufferSize;
    result.numIndices = indexBufferSize;
    result.vertexBuffer = outVertexBuffer;
    result.indexBuffer = outIndexBuffer;

    return result;
}
