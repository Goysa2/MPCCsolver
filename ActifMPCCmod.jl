module ActifMPCCmod

import NLPModels
import Relaxation

"""
Type MPCC_actif : problème MPCC pénalisé avec slack et ensemble des contraintes actives

liste des constructeurs :
MPCC_actif(nlp::NLPModels.AbstractNLPModel,r::Float64,s::Float64,t::Float64,nb_comp::Int64)
MPCC_actif(nlp::NLPModels.AbstractNLPModel,r::Float64,s::Float64,t::Float64,w::Any)

liste des méthodes :
updatew(ma::MPCC_actif)
setf(ma::MPCC_actif, f::Function, xj::Any)
setw(ma::MPCC_actif, w::Any)

liste des accesseurs :
evalx(ma::MPCC_actif,x::Vector)
evald(ma::MPCC_actif,d::Vector)
redd(ma::MPCC_actif,d::Vector)
obj(ma::MPCC_actif,x::Vector)
grad(ma::MPCC_actif,x::Vector)

liste des fonctions :
LSQComputationMultiplier(ma::MPCC_actif,gradpen::Vector,xj::Vector)
RelaxationRule(ma::ActifMPCCmod.MPCC_actif,xj::Vector,lg::Vector,lh::Vector,lphi::Vector,wmax::Any)
PasMax(ma::MPCC_actif,x::Vector,d::Vector)
AlphaChoix(alpha::Float64,alpha1::Float64,alpha2::Float64)
AlphaChoix(alpha::Float64,alpha1::Float64,alpha2::Float64,alpha3::Float64,alpha4::Float64)
PasMaxComp(ma::MPCC_actif,x::Vector,d::Vector)
"""

#TO DO List :
#Major :
#- Changer les w en set ou en liste
#- intégrer les contraintes de bornes sur x dans PasMax
#Minor :
#- copie de code dans PasMax
#- Plutôt que de passer le point courant -> stocker en point initial de mpcc ?

type MPCC_actif
 nlp::NLPModels.AbstractNLPModel # en fait on demande juste une fonction objectif, point initial, contraintes de bornes
 r::Float64
 s::Float64
 t::Float64
 w::Any #matrice à 2 colonnes et de longueur 2nb_comp -- clairement devrait être des listes ou des ensembles !
 bar_w::Vector # vecteur de longueur 2nb_comp -- clairement devrait être des listes ou des ensembles ! -- UTILE ?
 n::Int64 #dans le fond est optionnel si on a nb_comp
 nb_comp::Int64
 #ensembles d'indices :
 w1::Any # ensemble des indices (entre 0 et nb_comp) où la contrainte yG>=-r est active
 w2::Any # ensemble des indices (entre 0 et nb_comp) où la contrainte yH>=-r est active
 w3::Any # ensemble des indices (entre 0 et nb_comp) où la contrainte yG<=s+t*theta(yH,r) est active
 w4::Any # ensemble des indices (entre 0 et nb_comp) où la contrainte yH<=s+t*theta(yG,r) est active
 wcomp::Any #ensemble des indices (entre 0 et nb_comp) où la contrainte Phi<=0 est active
 w13c::Any #ensemble des indices où les variables yG sont libres
 w24c::Any #ensemble des indices où les variables yH sont libres
 wc::Any #ensemble des indices des contraintes où yG et yH sont libres
 wcc::Any #ensemble des indices des contraintes où yG et yH sont fixés
 wnew::Any #dernières contraintes ajoutés

 #paramètres pour la minimisation sans contrainte
 ite_max::Int64 #nombre maximum d'itération pour la recherche linéaire >= 0
 tau_armijo::Float64 #paramètre pour critère d'Armijo doit être entre (0,0.5)
 armijo_update::Float64 ##step=step_0*(1/2)^m
 # idée : on devrait peut-être garder une copie du paramètre rho ici !?
end

"""
Constructeur recommandé pour MPCC_actif
"""
function MPCC_actif(nlp::NLPModels.AbstractNLPModel,r::Float64,s::Float64,t::Float64,nb_comp::Int64)

  n=length(nlp.meta.x0)-2*nb_comp
  xk=nlp.meta.x0[1:n]
  ygk=nlp.meta.x0[n+1:n+nb_comp]
  yhk=nlp.meta.x0[n+nb_comp+1:n+2*nb_comp]
  w=sparse(zeros(2*nb_comp,2))

  for l=1:nb_comp
   if ygk[l]==nlp.meta.lvar[n+l]
    w[l,1]=1;
   elseif ygk[l]==Relaxation.psi(yhk[l],r,s,t)
    w[l+nb_comp,1]=1;
   end
   if yhk[l]==nlp.meta.lvar[n+l+nb_comp]
    w[l,2]=1;
   elseif yhk[l]==Relaxation.psi(ygk[l],r,s,t)
    w[l+nb_comp,2]=1;
   end
  end

 return MPCC_actif(nlp,r,s,t,w)
end

function MPCC_actif(nlp::NLPModels.AbstractNLPModel,r::Float64,s::Float64,t::Float64,w::Any)

 bar_w=find(x->x==0,w[:,1]+w[:,2])
 nb_comp=Int(size(w,1)/2)
 n=length(nlp.meta.x0)-2*nb_comp
 w1=find(x->x>0,w[1:nb_comp,1])
 w2=find(x->x>0,w[1:nb_comp,2])
 w3=find(x->x>0,w[nb_comp+1:2*nb_comp,1])
 w4=find(x->x>0,w[nb_comp+1:2*nb_comp,2])
 wcomp=find(x->x>=1,w[nb_comp+1:2*nb_comp,1]+w[nb_comp+1:2*nb_comp,2])
 w13c=find(x->x==0,w[1:nb_comp,1]+w[nb_comp+1:2*nb_comp,1])
 w24c=find(x->x==0,w[1:nb_comp,2]+w[nb_comp+1:2*nb_comp,2]) 
 wc=find(x->x==0, w[1:nb_comp,1]+w[1:nb_comp,2]+w[nb_comp+1:2*nb_comp,1]+w[nb_comp+1:2*nb_comp,2])
 wcc=find(x->x==2, w[1:nb_comp,1]+w[1:nb_comp,2]+w[nb_comp+1:2*nb_comp,1]+w[nb_comp+1:2*nb_comp,2])
 wnew=[]
 ite_max=4000
 tau_armijo=0.4
 armijo_update=0.9

 return MPCC_actif(nlp,r,s,t,w,bar_w,n,nb_comp,w1,w2,w3,w4,wcomp,w13c,w24c,wc,wcc,wnew,ite_max,tau_armijo,armijo_update)
end

"""
Methodes pour le MPCC_actif
"""
#Mise à jour des composantes liés à w
function updatew(ma::MPCC_actif)

 ma.bar_w=find(x->x==0,ma.w[:,1]+ma.w[:,2])
 ma.w1=find(x->x>0,ma.w[1:ma.nb_comp,1])
 ma.w2=find(x->x>0,ma.w[1:ma.nb_comp,2])
 ma.w3=find(x->x>0,ma.w[ma.nb_comp+1:2*ma.nb_comp,1])
 ma.w4=find(x->x>0,ma.w[ma.nb_comp+1:2*ma.nb_comp,2])
 ma.wcomp=find(x->x>=1,ma.w[ma.nb_comp+1:2*ma.nb_comp,1]+ma.w[ma.nb_comp+1:2*ma.nb_comp,2])
 ma.w13c=find(x->x==0,ma.w[1:ma.nb_comp,1]+ma.w[ma.nb_comp+1:2*ma.nb_comp,1])
 ma.w24c=find(x->x==0,ma.w[1:ma.nb_comp,2]+ma.w[ma.nb_comp+1:2*ma.nb_comp,2]) 
 ma.wc=find(x->x==0, ma.w[1:ma.nb_comp,1]+ma.w[1:ma.nb_comp,2]+ma.w[ma.nb_comp+1:2*ma.nb_comp,1]+ma.w[ma.nb_comp+1:2*ma.nb_comp,2])
 ma.wcc=find(x->x==2, ma.w[1:ma.nb_comp,1]+ma.w[1:ma.nb_comp,2]+ma.w[ma.nb_comp+1:2*ma.nb_comp,1]+ma.w[ma.nb_comp+1:2*ma.nb_comp,2])
 return ma
end

# Fonction qui met à jouer le MPCC_Actif au changement de fonction objectif
function setf(ma::MPCC_actif, f::Function, xj::Any)
  pen_mpcc = NLPModels.ADNLPModel(x->f(x), xj, lvar=ma.nlp.meta.lvar, uvar=ma.nlp.meta.uvar)
  ma.nlp=pen_mpcc
end

#Mise à jour de w
function setw(ma::MPCC_actif, w::Any)
 ma.wnew=max(w-ma.w,zeros(2*ma.nb_comp,2))
 ma.w=w
 return updatew(ma)
end

"""
Renvoie le vecteur x=[x,yg,yh] au complet
"""
function evalx(ma::MPCC_actif,x::Vector)
 #construction du vecteur de taille n+2nb_comp que l'on évalue :
 xf=ma.s*ones(ma.n+2*ma.nb_comp)
 xf[1:ma.n]=x[1:ma.n]
 xf[ma.w13c+ma.n]=x[ma.n+1:ma.n+length(ma.w13c)]
 xf[ma.w24c+ma.n+ma.nb_comp]=x[ma.n+length(ma.w13c)+1:ma.n+length(ma.w13c)+length(ma.w24c)]

 #on regarde les variables yG fixées :
 xf[ma.w1+ma.n]=ma.nlp.meta.lvar[ma.w1+ma.n]
 xf[ma.w3+ma.n]=Relaxation.psi(xf[ma.w3+ma.n+ma.nb_comp],ma.r,ma.s,ma.t)
 #on regarde les variables yH fixées :
 xf[ma.w2+ma.n+ma.nb_comp]=ma.nlp.meta.lvar[ma.w2+ma.n+ma.nb_comp]
 xf[ma.w4+ma.n+ma.nb_comp]=Relaxation.psi(xf[ma.w4+ma.n],ma.r,ma.s,ma.t)

 return xf
end

"""
Renvoie la direction d au complet
"""
function evald(ma::MPCC_actif,d::Vector)
 df=zeros(ma.n+2*ma.nb_comp)
 df[1:ma.n]=d[1:ma.n]
 df[ma.w13c+ma.n]=d[ma.n+1:ma.n+length(ma.w13c)]
 df[ma.w24c+ma.nb_comp+ma.n]=d[ma.n+length(ma.w13c)+1:ma.n+length(ma.w13c)+length(ma.w24c)]
 return df
end

"""
Renvoie la direction d réduite
"""
function redd(ma::MPCC_actif,d::Vector)
 df=zeros(ma.n+length(ma.w13c)+length(ma.w24c))
 df[1:ma.n]=d[1:ma.n]
 df[ma.n+1:ma.n+length(ma.w13c)]=d[ma.w13c+ma.n]
 df[ma.n+length(ma.w13c)+1:ma.n+length(ma.w13c)+length(ma.w24c)]=d[ma.w24c+ma.nb_comp+ma.n]
 return df
end

"""
Evalue la fonction objectif d'un MPCC actif : x
"""
function obj(ma::MPCC_actif,x::Vector)
 sol=0.0
 if length(x)==ma.n+2*ma.nb_comp
  sol=NLPModels.obj(ma.nlp,x)
 else
  sol=NLPModels.obj(ma.nlp,evalx(ma,x))
 end
 return sol
end

"""
Evalue le gradient de la fonction objectif d'un MPCC actif
x est le vecteur réduit
"""
function grad(ma::MPCC_actif,x::Vector)

 #on calcul xf le vecteur complet
 xf=evalx(ma,x)
 #construction du vecteur gradient de taille n+2nb_comp
 gradf=NLPModels.grad(ma.nlp,xf)

 # Conditionnelles pour gérer le cas où w1 et w3 est vide
 if isempty(ma.w1) && isempty(ma.w3)
  gradg=zeros(length(ma.w13c))
 elseif !isempty(ma.w13c)
  gradg=vcat(zeros(length(ma.w1)),Relaxation.dpsi(xf[ma.w3+ma.n+ma.nb_comp],ma.r,ma.s,ma.t).*gradf[ma.w3+ma.n])
 else #ma.w13c est vide
  gradg=[]
 end

 if isempty(ma.w2) && isempty(ma.w4)
  gradh=zeros(length(ma.w24c))
 elseif !isempty(ma.w24c)
  gradh=vcat(zeros(length(ma.w2)),Relaxation.dpsi(xf[ma.w4+ma.n],ma.r,ma.s,ma.t).*gradf[ma.w4+ma.nb_comp+ma.n])
 else
  gradh=[]
 end

 return vcat(gradf[1:ma.n],gradf[ma.w13c+ma.n]+gradg,gradf[ma.w24c+ma.nb_comp+ma.n]+gradh)
end



"""
LSQComputationMultiplier(ma::MPCC_actif,x::Vector) :
ma MPCC_Actif
xj in n+2nb_comp
gradpen in n+2nb_comp

calcul la valeur des multiplicateurs de Lagrange pour la contrainte de complémentarité en utilisant moindre carré
"""
function LSQComputationMultiplier(ma::MPCC_actif,gradpen::Vector,xj::Vector)

 gx,gy=Relaxation.dphi(xj[ma.n+1:ma.n+ma.nb_comp],xj[ma.n+ma.nb_comp+1:ma.n+2*ma.nb_comp],ma.r,ma.s,ma.t)

#point initial
# l_init=ones(3*ma.nb_comp)
# w1c=find(x->x==0,ma.w[1:ma.nb_comp,1])
# l_init[w1c]==zeros(size(w1c))
# w2c=find(x->x==0,ma.w[1:ma.nb_comp,2])
# l_init[ma.nb_comp+w2c]==zeros(size(w2c))
# wcompc=find(x->x==0,ma.w[ma.nb_comp+1:2*ma.nb_comp,1]+ma.w[ma.nb_comp+1:2*ma.nb_comp,2])
# l_init[2*ma.nb_comp+wcompc]=zeros(size(wcompc))

 # calcul moindre carrés
# lsqobjg(lg,lphi)=[gradpen[ma.w1+ma.n]-lg[ma.w1];gradpen[ma.wcomp+ma.n]+lphi[ma.wcomp].*collect(gx)[ma.wcomp]]
# lsqobjh(lh,lphi)=[gradpen[ma.w2+ma.n+ma.nb_comp]-lh[ma.w2];gradpen[ma.wcomp+ma.n+ma.nb_comp]+lphi[ma.wcomp].*collect(gy)[ma.wcomp]]
# lsqobj(lg,lh,lphi)=[lsqobjg(lg,lphi);lsqobjh(lh,lphi)]
#on attend en entrée un vecteur l de taille 3nb_comp
# lsqobj(l)=lsqobj(l[1:ma.nb_comp],l[ma.nb_comp+1:2*ma.nb_comp],l[2*ma.nb_comp+1:3*ma.nb_comp])
# Pas nécessaire : on utilise la formule de pseudo-inverse.
# lambda_pb = NLPModels.ADNLPModel(l->0.5*norm(lsqobj(l))^2, l_init)
# model_lsq = NLPModels.NLPtoMPB(lambda_pb, Ipopt.IpoptSolver(print_level=0))
# MathProgBase.optimize!(model_lsq)
# stat = MathProgBase.status(model_lsq)
# if stat == :Optimal
#  lk = MathProgBase.getsolution(model_lsq)
# else
#  println("Error LSQComputationMultiplier ",stat)
# end

 #matrices des contraintes actives : (lg,lh,lphi)'*A=b
 nw1=length(ma.w1)
 nw2=length(ma.w2)
 nwcomp=length(ma.wcomp)
 Dlg=-diagm(ones(nw1))
 Dlh=-diagm(ones(nw2))
 Dlphig=diagm(collect(gx)[ma.wcomp])
 Dlphih=diagm(collect(gy)[ma.wcomp])
 A=[hcat(Dlg,zeros(nw1,nw2+2*nwcomp));hcat(zeros(nw2,nw1),Dlh,zeros(nw2,2*nwcomp));hcat(zeros(nwcomp,nw1+nw2),Dlphig,Dlphih)] # nw1+nw2+nwcomp x nw1+nw2+2nwcomp
 #second membre
 b=-[gradpen[ma.w1+ma.n];gradpen[ma.wcomp+ma.n];gradpen[ma.w2+ma.n+ma.nb_comp];gradpen[ma.wcomp+ma.n+ma.nb_comp]] #nw1+nw2+2nwcomp
 #on calcule la solution par pseudo-inverse :
 l=pinv(A')*b

 lk=zeros(3*ma.nb_comp)
 lk[ma.w1]=l[1:nw1]
 lk[ma.nb_comp+ma.w2]=l[nw1+1:nw1+nw2]
 lk[2*ma.nb_comp+ma.wcomp]=l[nw1+nw2+1:nw1+nw2+nwcomp]
 
 return lk[1:ma.nb_comp],lk[ma.nb_comp+1:2*ma.nb_comp],lk[2*ma.nb_comp+1:3*ma.nb_comp]
end

"""
Définit la règle de relaxation de l'ensemble des contraintes
RelaxationRule(ma::ActifMPCCmod.MPCC_actif,xj::Vector,lg,lh,lphi,wmax)
xj          : de taille n+2nb_comp
(lg,lh,phi) : valeur multiplicateurs
wmax        : ensemble des contraintes qui viennent d'être ajouté

output : MPCC_actif (avec les ensembles de contraintes actives mis à jour
"""
function RelaxationRule(ma::ActifMPCCmod.MPCC_actif,xj::Vector,lg::Vector,lh::Vector,lphi::Vector,wmax::Any)

  copy_wmax=copy(wmax)

  # Relaxation de l'ensemble d'activation : désactive toutes les contraintes négatives
  ma.w[find(x -> x<0,[lg;lphi;lh;lphi])]=zeros(length(find(x -> x<0,[lg;lphi;lh;lphi])))
  # Règle d'anti-cyclage : on enlève pas une contrainte qui vient d'être ajouté.
  ma.w[find(x->x==1.0,copy_wmax)]=ones(length(find(x->x==1.0,copy_wmax)))

 return ActifMPCCmod.updatew(ma)
end

"""
Calcul le pas maximum que l'on peut prendre dans une direction d (par rapport à la contrainte de complémentarité relaxé)
d : direction réduit
xj : itéré réduit

output :
alpha : le pas maximum
w_save : l'ensemble des contraintes qui vont devenir actives si choisit alphamax
"""
function PasMaxComp(ma::MPCC_actif,x::Vector,d::Vector)

 #initialisation
 alpha=Inf #pas maximum que l'on peut prendre
 w_save=copy(ma.w) #double tableau des indices avec les contraintes activent en x+alpha*d

 #les indices où la première composante est libre
 for i in ma.w13c
  bloque=(i in ma.w2) && (i in ma.w4)
  if !(i in ma.w24c) && !bloque && d[i+ma.n]<0
   #on prend le plus petit entre x+alpha*dx>=-r et s+tTheta(x+alpha*dx-s)>=-r
   alpha11=(ma.nlp.meta.lvar[ma.n+i]-x[i+ma.n])/d[i+ma.n]
   alpha12=(Relaxation.invpsi(ma.nlp.meta.lvar[ma.n+i],ma.r,ma.s,ma.t)-x[i+ma.n])/d[i+ma.n]

   alphag=AlphaChoix(alpha,alpha11,alpha12)
   if alphag<=alpha
    alpha=alphag
    w_save=copy(ma.w)
   end

   #update of the active set
   if alpha11==alpha
    w_save[i,1]=1
   end
   if alpha12==alpha
    w_save[i+ma.nb_comp,2]=1
    w_save[i,2]=1
   end

  elseif bloque
   alpha=0.0
  end
 end

 #c'est un copie coller d'au dessus => exporter dans une fonction
 #les indices où la deuxième composante est libre
 for i in ma.w24c
  bloque=(i in ma.w1) && (i in ma.w3)
  if !(i in ma.w13c) && !bloque && d[i+length(ma.w13c)+ma.n]<0
   #on prend le plus petit entre y+alpha*dy>=-r et s+tTheta(y+alpha*dy-s)>=-r
   alpha21=(ma.nlp.meta.lvar[ma.n+length(ma.w13c)+i]-x[i+length(ma.w13c)+ma.n])/d[i+length(ma.w13c)+ma.n]
   alpha22=(Relaxation.invpsi(ma.nlp.meta.lvar[ma.n+length(ma.w13c)+i],ma.r,ma.s,ma.t)-x[i+length(ma.w13c)+ma.n])/d[i+length(ma.w13c)+ma.n]

   alphah=AlphaChoix(alpha,alpha21,alpha22)
   if alphah<=alpha
    alpha=alphah
    w_save=copy(ma.w)
   end

   #on met à jour les contraintes
   if alpha21==alpha
    w_save[i,2]=1
   end
   if alpha22==alpha
    w_save[i+ma.nb_comp,1]=1
    w_save[i,1]=1
   end
  elseif bloque
   alpha=0.0
  end
 end

 #enfin les indices où les deux sont libres
 for i in ma.wc
  #yG-psi(yH)=0 ou yH-psi(yG)=0
  alphac=Relaxation.AlphaThetaMax(x[i+ma.n],d[i+ma.n],x[i+length(ma.w13c)+ma.n],d[i+length(ma.w13c)+ma.n],ma.r,ma.s,ma.t)
  #yG-tb=0
  alphac11=d[i+ma.n]<0 ? (ma.nlp.meta.lvar[ma.n+i]-x[i+ma.n])/d[i+ma.n] : Inf
  #yH-tb=0
  alphac21=d[i+length(ma.w13c)+ma.n]<0 ? (ma.nlp.meta.lvar[ma.n+length(ma.w13c)+i]-x[i+length(ma.w13c)+ma.n])/d[i+length(ma.w13c)+ma.n] : Inf  

  alphagh=AlphaChoix(alpha,alphac[1],alphac[2],alphac11,alphac21)

  if alphagh<=alpha
   alpha=alphagh
   w_save=copy(ma.w)
  end

   if alphac[1]==alpha
    w_save[i+ma.nb_comp,1]=1
   end
   if alphac[2]==alpha
    w_save[i+ma.nb_comp,2]=1
   end
   if alphac11==alpha
    w_save[i,1]=1
   end
   if alphac21==alpha
    w_save[i,2]=1
   end

 end #fin boucle for ma.wc

 return alpha,w_save,w_save-ma.w
end

"""
Met à jour alpha si :
1) il est plus petit
2) il est non-nul
"""
function AlphaChoix(alpha::Float64,alpha1::Float64,alpha2::Float64)
 return AlphaChoix(alpha,alpha1,alpha2,0.0,0.0)
end

function AlphaChoix(alpha::Float64,alpha1::Float64,alpha2::Float64,alpha3::Float64,alpha4::Float64)
 prec=eps(Float64)
 a=alpha1,alpha2,alpha3,alpha4
 a=a[find(x->x>=prec,collect(a))]
 if isempty(a)
  println(alpha1,alpha2,alpha3,alpha4)
  a=max(alpha1,alpha2,alpha3,alpha4)
 end

 return min(minimum(a),alpha)
end

"""
Calcul le pas maximum que l'on peut prendre dans une direction d
d : direction réduit
xj : itéré réduit

output :
alpha : le pas maximum
w_save : l'ensemble des contraintes qui vont devenir actives si choisit alphamax
"""
function PasMax(ma::MPCC_actif,x::Vector,d::Vector)
 #on récupère les infos sur la contrainte de complémentarité
 alpha,w_save,w_new=PasMaxComp(ma,x,d)
 
 if alpha<0.0
  println("PasMax error: pas maximum négatif.")
  return
 end

 return alpha,w_save,w_new
end

#end of module
end