"""
+solve(mod::MPCCmod.MPCC)

-solve_subproblem(inst::MPCCSolvemod.MPCCSolve,
                 r::Float64,s::Float64,t::Float64,
                 rho::Vector)
-warning_print(realisable::Bool,solved::Bool,param::Bool,optimal::Bool)
-final_message(or::OutputRelaxationmod.OutputRelaxation,
               solved::Bool,optimal::Bool,realisable::Bool)
"""

module MPCCsolve

using MPCCmod
using OutputRelaxationmod
using MPCCSolvemod

#TO DO
# - est-ce qu'on pourrait avoir la possibilité d'avoir (r,s,t) en variable ?
# - pourquoi on évalue f dans le solve ?

"""
Methode de relaxation pour resoudre :
"""
function solve(mod::MPCCmod.MPCC)

 #initialization
 (r,s,t)=mod.paramset.initrst()

 rho=mod.paramset.rho_init
 x0=mod.mp.meta.x0; xk=x0
 pmin=mod.paramset.paramin

 real=MPCCmod.viol_contrainte_norm(mod,x0)

 realisable=real<=mod.paramset.precmpcc
 solved=true
 param=true

 f=MPCCmod.obj(mod,x0)
 or=OutputRelaxationmod.OutputRelaxation(x0,real, f)

 #heuristic in case the initial point is the solution
 optimal=realisable && MPCCmod.stationary_check(mod,x0) #reste à checker le signe des multiplicateurs

 MPCCsolveinst=MPCCSolvemod.MPCCSolve(mod)

 #Major Loop
 j=0
 while param && !(realisable && solved && optimal)

  xk,solved,rho,output = solve_subproblem(MPCCsolveinst,r,s,t,rho)

  real=MPCCmod.viol_contrainte_norm(mod,xk[1:mod.n])
  f=MPCCmod.obj(mod,xk[1:mod.n])

  or=OutputRelaxationmod.UpdateOR(or,xk[1:mod.n],0,r,s,t,mod.paramset.prec_oracle(r,s,t,mod.paramset.precmpcc),real,output,f)

  mod=MPCCmod.addInitialPoint(mod,xk[1:mod.n]) #met à jour le MPCC avec le nouveau point

  (r,s,t)=mod.paramset.updaterst(r,s,t)

  solved=true in isnan.(xk)?false:solved
  realisable=real<=mod.paramset.precmpcc

  optimal=!isnan(f) && !(true in isnan.(xk)) && MPCCmod.stationary_check(mod,xk[1:mod.n])
  param=(t+r+s)>pmin

  j+=1
 end
 #End Major Loop

 mod.paramset.verbose != 0.0 ? warning_print(realisable,solved,param,optimal) : nothing

 or=final_message(or,solved::Bool,optimal::Bool,realisable::Bool)

 #Traitement final :
 OutputRelaxationmod.Print(or,mod.n,mod.paramset.verbose)

 mod=MPCCmod.addInitialPoint(mod,x0[1:mod.n]) #remet le point initial du MPCC
 nb_eval=[mod.mp.counters.neval_obj,mod.mp.counters.neval_cons,
          mod.mp.counters.neval_grad,mod.mp.counters.neval_hess,
          mod.G.counters.neval_cons,mod.G.counters.neval_jac,
          mod.H.counters.neval_cons,mod.H.counters.neval_jac]

 # output
 return xk, f, or, nb_eval
end

"""
Methode pour résoudre le sous-problème relaxé :
"""
function solve_subproblem(inst::MPCCSolvemod.MPCCSolve,
                          r::Float64,s::Float64,t::Float64,
                          rho::Vector)
 return inst.solve_sub_pb(inst.mod,r,s,t,rho,inst.name_relax) #renvoie xk,stat
end

"""
Function that prints some warning
"""
function warning_print(realisable::Bool,solved::Bool,param::Bool,optimal::Bool)

	 realisable || print_with_color(:green,"Infeasible solution: (comp,cons)=($(MPCCmod.viol_comp(mod,xk)),$(MPCCmod.viol_cons(mod,xk)))\n" )
	 solved || print_with_color(:green,"Subproblem failure. NaN in the solution ? $(true in isnan(xk)). Stationary ? $(realisable && optimal)\n")
	 param || realisable || print_with_color(:green,"Parameters too small\n") 
	 solved && realisable && optimal && print_with_color(:green,"Success\n")
 return
end

function final_message(or::OutputRelaxationmod.OutputRelaxation,
                       solved::Bool,optimal::Bool,realisable::Bool)

 if solved && optimal && realisable
  or=OutputRelaxationmod.UpdateFinalOR(or,"Success")
 elseif optimal && realisable
  or=OutputRelaxationmod.UpdateFinalOR(or,"Success (with sub-pb failure)")
 elseif !realisable
  or=OutputRelaxationmod.UpdateFinalOR(or,"Infeasible")
 elseif realisable && !optimal
  or=OutputRelaxationmod.UpdateFinalOR(or,"Feasible, but not optimal")
 else
  or=OutputRelaxationmod.UpdateFinalOR(or,"autres")
 end

 return or
end

#end of module
end
