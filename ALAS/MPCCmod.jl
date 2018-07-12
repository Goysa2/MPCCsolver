module MPCCmod

using NLPModels

import ParamSetmod
import AlgoSetmod

"""
Definit le type MPCC :
min_x f(x)
l <= x <= u
lb <= c(x) <= ub
0 <= G(x) _|_ H(x) >= 0

liste des constructeurs :
MPCC(f::Function,x0::Vector,
     G::NLPModels.AbstractNLPModel,H::NLPModels.AbstractNLPModel,
     nb_comp::Int64,
     lvar::Vector,uvar::Vector,
     c::Function,lcon::Vector,ucon::Vector)
MPCC(mp::NLPModels.AbstractNLPModel,
     G::NLPModels.AbstractNLPModel,H::NLPModels.AbstractNLPModel,nb_comp)
MPCC(mp::NLPModels.AbstractNLPModel)
MPCC(mp::NLPModels.AbstractNLPModel,algo::AlgoSetmod.AlgoSet)
MPCC(mp::NLPModels.AbstractNLPModel,
     G::NLPModels.AbstractNLPModel,H::NLPModels.AbstractNLPModel;nb_comp::Float64=NaN)

liste des accesseurs :
addInitialPoint(mod::MPCC,x0::Vector)
obj(mod::MPCC,x::Vector)
grad(mod::MPCC,x::Vector)
jac_actif(mod::MPCC,x::Vector)

liste des fonctions :
viol_contrainte_norm(mod::MPCCmod.MPCC,x::Vector,yg::Vector,yh::Vector)
viol_contrainte_norm(mod::MPCCmod.MPCC,x::Vector)
viol_contrainte(mod::MPCCmod.MPCC,x::Vector,yg::Vector,yh::Vector)
viol_contrainte(mod::MPCCmod.MPCC,x::Vector)
viol_comp(mod::MPCCmod.MPCC,x::Vector)
viol_cons(mod::MPCCmod.MPCC,x::Vector)

dual_feasibility(mod::MPCC,x::Vector,l::Vector,A::Any)
sign_stationarity_check(mod::MPCC,x::Vector,l::Vector)
sign_stationarity_check(mod::MPCC,x::Vector,l::Vector,
                        Il::Array{Int64,1},Iu::Array{Int64,1},
                        Ig::Array{Int64,1},Ih::Array{Int64,1},
                        IG::Array{Int64,1},IH::Array{Int64,1})
stationary_check(mod::MPCC,x::Vector)
"""

# TO DO List
#Major :
# - appel de la hessienne d'un SimpleNLPModel ? NLPModels.hess(mod.H,x)

type MPCC

 mp::NLPModels.AbstractNLPModel
 G::NLPModels.AbstractNLPModel
 H::NLPModels.AbstractNLPModel

 xj::Vector #itéré courant

 nb_comp::Int64
 nbc::Int64
 n::Int64

 algoset::AlgoSetmod.AlgoSet
 paramset::ParamSetmod.ParamSet

end

#Constructeurs supplémentaires :
function MPCC(f::Function,x0::Vector,
              G::NLPModels.AbstractNLPModel,H::NLPModels.AbstractNLPModel,
              nb_comp::Int64,
              lvar::Vector,uvar::Vector,
              c::Function,lcon::Vector,ucon::Vector)

 mp=ADNLPModel(f, x0, lvar=lvar, uvar=uvar, c=c, lcon=lcon, ucon=ucon)
 nbc=length(mp.meta.lvar)+length(mp.meta.uvar)+length(mp.meta.lcon)+length(mp.meta.ucon)+2*nb_comp

 n=length(mp.meta.x0)

 return MPCC(mp,G,H,x0,nb_comp,nbc,n,AlgoSetmod.AlgoSet(),ParamSetmod.ParamSet(nbc))
end

function MPCC(mp::NLPModels.AbstractNLPModel,
              G::NLPModels.AbstractNLPModel,H::NLPModels.AbstractNLPModel,nb_comp)

 nbc=length(mp.meta.lvar)+length(mp.meta.uvar)+length(mp.meta.lcon)+length(mp.meta.ucon)+2*nb_comp
 n=length(mp.meta.x0)
 
 return MPCC(mp,G,H,mp.meta.x0,nb_comp,nbc,n,AlgoSetmod.AlgoSet(),ParamSetmod.ParamSet(nbc))
end

function MPCC(mp::NLPModels.AbstractNLPModel)

 #le plus "petit" SimpleNLPModel
 G=SimpleNLPModel(x->0, [0.0])
 H=SimpleNLPModel(x->0, [0.0])

 nb_comp=0
 nbc=length(mp.meta.lvar)+length(mp.meta.uvar)+length(mp.meta.lcon)+length(mp.meta.ucon)+2*nb_comp
 n=length(mp.meta.x0)

 return MPCC(mp,G,H,mp.meta.x0,nb_comp,nbc,n,
		AlgoSetmod.AlgoSet(),ParamSetmod.ParamSet(nbc))
end

function MPCC(mp::NLPModels.AbstractNLPModel,algo::AlgoSetmod.AlgoSet)

 #le plus "petit" SimpleNLPModel
 G=SimpleNLPModel(x->0, [0.0])
 H=SimpleNLPModel(x->0, [0.0])

 nb_comp=0
 nbc=length(mp.meta.lvar)+length(mp.meta.uvar)+length(mp.meta.lcon)+length(mp.meta.ucon)+2*nb_comp
 n=length(mp.meta.x0)

 return MPCC(mp,G,H,mp.meta.x0,nb_comp,nbc,n,
		AlgoSetmod.AlgoSet(),ParamSetmod.ParamSet(nbc))
end

function MPCC(mp::NLPModels.AbstractNLPModel,
              G::NLPModels.AbstractNLPModel,H::NLPModels.AbstractNLPModel;nb_comp::Float64=NaN)

 nb_comp=isnan(nb_comp)?length(NLPModels.cons(G,mp.meta.x0)):nb_comp
 nbc=length(mp.meta.lvar)+length(mp.meta.uvar)+length(mp.meta.lcon)+length(mp.meta.ucon)+2*nb_comp
 n=length(mp.meta.x0)

 return MPCC(mp,G,H,mp.meta.x0,nb_comp,nbc,n,
	     AlgoSetmod.AlgoSet(),ParamSetmod.ParamSet(nbc))
end

"""
Getteur
"""
function obj(mod::MPCC,x::Vector)
 return NLPModels.obj(mod.mp,x)
end
"""
gradient de la fonction objectif
"""
function grad(mod::MPCC,x::Vector)
 return NLPModels.grad(mod.mp,x)
end

"""
Jacobienne des contraintes actives à precmpcc près
"""

function jac_actif(mod::MPCC,x::Vector)
  prec=mod.paramset.precmpcc
  n=mod.n

  Il=find(z->norm(z-mod.mp.meta.lvar,Inf)<=prec,x)
  Iu=find(z->norm(z-mod.mp.meta.uvar,Inf)<=prec,x)
  jl=zeros(n);jl[Il]=1.0;Jl=diagm(jl);
  ju=zeros(n);jl[Iu]=1.0;Ju=diagm(ju);

  IG=[];IH=[];Ig=[];Ih=[];

 if mod.mp.meta.ncon+mod.nb_comp ==0

  A=[]

 else
  c=cons(mod.mp,x)
  Ig=find(z->norm(z-mod.mp.meta.lcon,Inf)<=prec,c)
  Ih=find(z->norm(z-mod.mp.meta.ucon,Inf)<=prec,c)
  Jg=NLPModels.jac(mod.mp,x)[Ig,1:n]
  Jh=NLPModels.jac(mod.mp,x)[Ih,1:n]

  if mod.nb_comp>0
   IG=find(z->norm(z-mod.G.meta.lcon,Inf)<=prec,NLPModels.cons(mod.G,x))
   IH=find(z->norm(z-mod.H.meta.lcon,Inf)<=prec,NLPModels.cons(mod.H,x))
   A=[Jl;Ju;-Jg;Jh; -NLPModels.jac(mod.G,x)[IG,1:n]; -NLPModels.jac(mod.H,x)[IH,1:n] ]'
  else
   A=[Jl;Ju;-Jg;Jh]'
  end
 end

 return A, Il,Iu,Ig,Ih,IG,IH
end

"""
Accesseur : modifie le point initial
"""

function addInitialPoint(mod::MPCC,x0::Vector)

 mod.xj=x0

 return mod
end

"""
Donne la norme 2 de la violation des contraintes avec slack

note : devrait appeler viol_contrainte
"""
function viol_contrainte_norm(mod::MPCC,x::Vector,yg::Vector,yh::Vector;tnorm::Real=2)
 return norm(viol_contrainte(mod,x,yg,yh),tnorm)
end

function viol_contrainte_norm(mod::MPCC,x::Vector;tnorm::Real=2) #x de taille n+2nb_comp

 n=mod.n
 if length(x)==n
  resul=max(viol_comp(mod,x),viol_cons(mod,x))
 else
  resul=viol_contrainte_norm(mod,x[1:n],x[n+1:n+mod.nb_comp],x[n+mod.nb_comp+1:n+2*mod.nb_comp],tnorm=tnorm)
 end
 return resul
end

"""
Donne le vecteur de violation des contraintes dans l'ordre : G(x)-yg ; H(x)-yh ; lvar<=x ; x<=uvar ; lvar<=c(x) ; c(x)<=uvar
"""
function viol_contrainte(mod::MPCC,x::Vector,yg::Vector,yh::Vector)

 c=NLPModels.cons(mod.mp,x)
 if mod.nb_comp>0
  G=NLPModels.cons(mod.G,x)
  H=NLPModels.cons(mod.H,x)
  return [G-yg;H-yh;max.(mod.mp.meta.lvar-x,0);max.(x-mod.mp.meta.uvar,0);max.(mod.mp.meta.lcon-c,0);max.(c-mod.mp.meta.ucon,0)]
 else
  return [yg;yh;max.(mod.mp.meta.lvar-x,0);max.(x-mod.mp.meta.uvar,0);max.(mod.mp.meta.lcon-c,0);max.(c-mod.mp.meta.ucon,0)]
 end

end

function viol_contrainte(mod::MPCC,x::Vector) #x de taille n+2nb_comp
 n=length(mod.mp.meta.x0)

 return viol_contrainte(mod,x[1:n],x[n+1:n+mod.nb_comp],x[n+mod.nb_comp+1:n+2*mod.nb_comp])
end

"""
Donne la norme de la violation de la complémentarité min(G,H)
"""
function viol_comp(mod::MPCC,x::Vector;tnorm::Real=2)

 n=mod.n
 x=length(x)==n?x:x[1:n]
 G=NLPModels.cons(mod.G,x)
 H=NLPModels.cons(mod.H,x)

 return mod.nb_comp>0?norm(G.*H./(G+H+1),tnorm):0
end

"""
Donne la norme de la violation des contraintes \"classiques\"
"""
function viol_cons(mod::MPCC,x::Vector;tnorm::Real=2)

 n=mod.n
 x=length(x)==n?x:x[1:n]
 feas=norm([max.(mod.mp.meta.lvar-x,0);max.(x-mod.mp.meta.uvar,0)],tnorm)

 if mod.mp.meta.ncon !=0

  c=NLPModels.cons(mod.mp,x)
  feas=max(norm([max.(mod.mp.meta.lcon-c,0);max.(c-mod.mp.meta.ucon,0)],tnorm),feas)

 end

 return feas
end

"""
Donne la violation de la réalisabilité dual (norme Infinie)
"""
function dual_feasibility(mod::MPCC,x::Vector,l::Vector,A::Any) #type général pour matrice ?

 b=grad(mod,x)

 return optimal=norm(A*l+b,Inf)<=mod.paramset.precmpcc
end
"""
Vérifie les signes de la M-stationarité (l entier)
"""
function sign_stationarity_check(mod::MPCC,x::Vector,l::Vector)

  prec=mod.paramset.precmpcc

  Il=find(z->norm(z-mod.mp.meta.lvar,Inf)<=prec,x)
  Iu=find(z->norm(z-mod.mp.meta.uvar,Inf)<=prec,x)

  IG=[];IH=[];Ig=[];Ih=[];

 if mod.mp.meta.ncon+mod.nb_comp >0

  c=cons(mod.mp,x)
  Ig=find(z->norm(z-mod.mp.meta.lcon,Inf)<=prec,c)
  Ih=find(z->norm(z-mod.mp.meta.ucon,Inf)<=prec,c)

  if mod.nb_comp>0
   IG=find(z->norm(z-mod.G.meta.lcon,Inf)<=prec,NLPModels.cons(mod.G,x))
   IH=find(z->norm(z-mod.H.meta.lcon,Inf)<=prec,NLPModels.cons(mod.H,x))
  end
 end

 #setdiff(∪(Il,Iu),∩(Il,Iu))
 l_pos=max.(l[1:2*n+2*mod.mp.meta.ncon],0)
 I_biactif=∩(IG,IH)
 lG=[2*n+2*mod.mp.meta.ncon+I_biactif]
 lH=[2*n+2*mod.mp.meta.ncon+mod.nb_comp+I_biactif]
 l_cc=min.(lG.*lH,max.(-lG,0)+max.(-lH,0))

 return norm([l_pos;l_cc],Inf)<=mod.paramset.precmpcc
end

"""
Vérifie les signes de la M-stationarité (l actif)
"""
function sign_stationarity_check(mod::MPCC,x::Vector,l::Vector,
                                 Il::Array{Int64,1},Iu::Array{Int64,1},
                                 Ig::Array{Int64,1},Ih::Array{Int64,1},
                                 IG::Array{Int64,1},IH::Array{Int64,1})

 nl=length(Il)+length(Iu)+length(Ig)+length(Ih)
 nccG=length(IG)
 nccH=length(IH)
 l_pos=max.(l[1:nl],0)
 I_biactif=∩(IG,IH)
 lG=l[I_biactif+nl]
 lH=l[nl+nccG+I_biactif]
 l_cc=min.(lG.*lH,max.(-lG,0)+max.(-lH,0))

 return norm([l_pos;l_cc],Inf)<=mod.paramset.precmpcc
end

"""
For a given x, compute the multiplier and check the feasibility dual
"""
function stationary_check(mod::MPCC,x::Vector)
 n=mod.n
 b=-grad(mod,x)

 if mod.mp.meta.ncon+mod.nb_comp ==0

  optimal=norm(b,Inf)<=mod.paramset.precmpcc

 else
  A, Il,Iu,Ig,Ih,IG,IH=jac_actif(mod,x)

  if !(true in isnan.(A) || true in isnan.(b))
   l=pinv(full(A))*b #pinv not defined for sparse matrix
   optimal=dual_feasibility(mod,x,l,A)
   good_sign=sign_stationarity_check(mod,x,l,Il,Iu,Ig,Ih,IG,IH)
  else
   @printf("Evaluation error: NaN in the derivative")
   optimal=false
  end
 end

 return optimal
end

#end du module
end
