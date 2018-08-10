function lsq_computation_multiplier_bool(ma  :: ActifMPCC,
                                         xjk :: Vector)

   gradpen = ma.ractif.gx

   l = _lsq_computation_multiplier(ma, gradpen, xjk)

   l_negative = findfirst(x->x<0, l) != 0

 return l, l_negative
end

function _lsq_computation_multiplier(ma      :: ActifMPCC,
                                     gradpen :: Vector,
                                     xj      :: Vector)

 r,s,t = ma.pen.r,ma.pen.s,ma.pen.t
 wn1 = ma.wn1
 wn2 = ma.wn2
 wcomp = ma.wcomp
 w1 = ma.w1
 w2 = ma.w2
 n, ncc = ma.n, ma.ncc

 dg = dphi(xj[ma.n+1:ma.n+ma.ncc],
           xj[ma.n+ma.ncc+1:ma.n+2*ma.ncc],
           r, s, t)

 gx = dg[1:ma.ncc]
 gy = dg[ma.ncc+1:2*ma.ncc]

 #matrices des contraintes actives : (lx,ux,lg,lh,lphi)'*A=b
 nx1 = length(ma.wn1)
 nx2 = length(ma.wn2)
 nx  = nx1 + nx2
 nw1 = length(ma.w1)
 nw2 = length(ma.w2)
 nwcomp = length(ma.wcomp)

 Jxl = -diagm(ones(n))[1:n,wn1]
 Jxu = diagm(ones(n))[1:n,wn2]

 JG  = -diagm(ones(ncc))[1:ncc,w1]
 JPG = diagm(collect(gx))[1:ncc,wcomp]
 JH  = -diagm(ones(ncc))[1:ncc,w2]
 JPH = diagm(collect(gy))[1:ncc,wcomp]

 Jx=hcat(Jxl, zeros(n,nx2+nw1+nw2+2*nwcomp)) + 
    hcat(zeros(n,nx1), Jxu, zeros(n,nw1+nw2+2*nwcomp))

 Tmpsg=hcat(zeros(ncc,nx),JG,zeros(ncc,nw2+2*nwcomp)) +
       hcat(zeros(ncc,nx+nw1+nw2),JPG,zeros(ncc,nwcomp))
 Tmpsh=hcat(zeros(ncc,nx+nw1),JH,zeros(ncc,2*nwcomp))+
       hcat(zeros(ncc,nx+nw1+nw2+nwcomp),JPH)

 J = vcat(Jx,Tmpsg,Tmpsh)

 #compute the multiplier using pseudo-inverse
 #l=J \ gradpen
 l = - pinv(J) * gradpen

 lk = zeros(2*n+3*ncc)

 lk[wn1]             = l[1:nx1]
 lk[n+wn2]           = l[nx1+1:nx]
 lk[2*n+w1]          = l[nx+1:nx+nw1]
 lk[2*n+ncc+w2]      = l[nx+nw1+1:nx+nw1+nw2]
 lk[2*n+2*ncc+wcomp] = l[nx+nw1+nw2+1:nx+nw1+nw2+nwcomp]


 return lk
end
