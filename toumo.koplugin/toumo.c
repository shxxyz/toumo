/* Optional accelerator for ARM Linux readers. All buffers are packed bytes
 * in display-independent orientation. 16-bit accumulation keeps layers additive. */
#include <stdint.h>
static int clamp(int v,int lo,int hi) { return v<lo?lo:v>hi?hi:v; }
void toumo_plate(const uint8_t *src,int stride,int w,int h,int left,int top,int right,int bottom,uint8_t *dst,int ds) {
    const int x0=clamp((w-right+1)/2,0,(w+1)/2), x1=clamp((w-left)/2,x0,(w+1)/2);
    const int y0=clamp((top+1)/2,0,(h+1)/2), y1=clamp(bottom/2,y0,(h+1)/2);
    for(int y=y0;y<y1;y++) {
        const uint8_t *a=src+2*y*stride;
        for(int x=x0;x<x1;x++) {
            const int i=w-2-2*x;
            dst[y*ds+x]=255-(a[i]+a[i+1]+a[i+stride]+a[i+stride+1]+2)/4;
        }
    }
}
void toumo_add_layer(uint16_t *sum,const uint8_t *plate,int stride,int w,int h,int depth) {
    static const int weights[]={256,112,52,24};
    for(int y=0;y<h;y++) {
        const uint8_t *row=plate+y*stride;
        for(int x=0;x<w;x++) {
            const int i=(depth&1)?x:w-1-x;
            sum[y*w+x]+=(uint16_t)((unsigned)(row[i]*weights[depth-1]) >> 8);
        }
    }
}
/* A separable 1:2:1 filter models the spread of ink through the paper. */
void toumo_soften(uint16_t *sum,uint16_t *tmp,int w,int h) {
    for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
        const uint16_t *r=sum+y*w;
        tmp[y*w+x]=(r[x?x-1:0]+2*r[x]+r[x+1<w?x+1:x]+2)/4;
    }
    for(int y=0;y<h;y++) {
        const uint16_t *a=tmp+(y?y-1:y)*w,*b=tmp+y*w,*c=tmp+(y+1<h?y+1:y)*w;
        for(int x=0;x<w;x++) sum[y*w+x]=(a[x]+2*b[x]+c[x]+2)/4;
    }
}
void toumo_mask(const uint16_t *sum,int w,int h,const uint8_t *paper,int texture,int strength,uint8_t *mask,int stride,int had_paper) {
    static const int bayer[]={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5};
    uint8_t quant[16][128];
    for(int phase=0;phase<16;phase++) for(int i=0;i<128;i++)
        quant[phase][i]=(uint8_t)(17*((32*i+(2*bayer[phase]+1)*17)/(32*17)));
    const int cols=(w+1)/2,rows=(h+1)/2;
    for(int y=0;y<h;y++) {
        int ty=y&1023; if(ty>=512) ty=1023-ty;
        const uint8_t *grain=paper?paper+ty*512:0;
        const uint16_t *r=sum+(y/2)*cols,*b=sum+clamp(y/2+1,0,rows-1)*cols;
        uint8_t *alpha=mask+y*stride+1;
        for(int x=0;x<w;x++) {
            int i=x/2,j=i+1<cols?i+1:i;
            int val=(y&1)?r[i]+b[i]:2*r[i];
            val=(x&1)?val+((y&1)?r[j]+b[j]:2*r[j]):2*val;
            if(had_paper && !val) continue;
            if(val>1020) val=1020;
            int tx=x&1023; if(tx>=512) tx=1023-tx;
            const int pigment=grain?4*grain[tx]*texture:0;
            const int gray=(val*strength+pigment+510)/1020;
            alpha[2*x]=quant[((y&3)<<2)+(x&3)][gray];
        }
    }
}
/* Apply a black alpha stencil to a normal 8-bit reading surface. Keep the
 * fast transparent case and use rounded integer /255 for antialiased text. */
void toumo_apply(uint8_t *dst,int ds,const uint8_t *mask,int ms,int w,int h) {
    for(int y=0;y<h;y++) {
        uint8_t *row=dst+y*ds; const uint8_t *a=mask+y*ms+1;
        for(int x=0;x<w;x++) {
            const unsigned int v=row[x]*(255U-a[2*x])+128;
            row[x]=(uint8_t)((v+(v>>8))>>8);
        }
    }
}
