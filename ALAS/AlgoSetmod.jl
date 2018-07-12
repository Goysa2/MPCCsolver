module AlgoSetmod

using Penalty
using DDirection
using LineSearch
using ScalingDual
using UnconstrainedStopping
using CRhoUpdate

"""
AlgoSet()
AlgoSet(penalty::Function,direction::Function, linesearch::Function)

Commentaires :
Liste les choix algorithmiques utilisés dans la résolution du MPCC :
* choix de la fonction de pénalité
* choix de la direction de descente
* choix de la recherche linéaire
* choix de la méthode de scaling sur la réalisabilité duale
* précision du pb pénalisé sans contraintes
* c(x)*rho tronqué
"""

type AlgoSet

 penalty::Function
 direction::Function
 linesearch::Function

 scaling_dual::Function
 unconstrained_stopping::Function
 crho_update::Function
end

#Constructeur par défaut
function AlgoSet()

  penalty=Penalty.Quadratic
  direction=DDirection.NwtdirectionSpectral
  linesearch=LineSearch.ArmijoWolfe
  scaling_dual=ScalingDual.NoScaling
  uncons_stopping=UnconstrainedStopping.Prec
  crho_update=CRhoUpdate.MinProd

 return AlgoSet(penalty,direction,linesearch,
                scaling_dual,uncons_stopping,crho_update)
end

function AlgoSet(penalty::Function,direction::Function, linesearch::Function)

  scaling_dual=ScalingDual.ParamScaling
  uncons_stopping=UnconstrainedStopping.ScalePrec
  crho_update=CRhoUpdate.MinProd

 return AlgoSet(penalty,direction, linesearch,
                scaling_dual,uncons_stopping,crho_update)
end

#end of module
end
