import sys
p=(1<<64)-(1<<32)+1
N=int(sys.argv[1])
x=(305419896<<32)|2596069104; y=(4275878552<<32)|1985229328
assert x<p and y<p
r=(x*pow(y,N,p))%p
print(r>>32, r&0xffffffff)
