#' run LIME model - simulation mode
#'
#' \code{run_LIME} run length-based integrated mixed-effects model with generated data
#'
#' @param modpath model directory
#' @param lh list of life history information, from create_lh_list
#' @param input_data tagged list of data inputs. Required: years = vector of years (true years or indices); LF = matrix of length frequency (years along rows and length bins along columns), obs_per_year = vector of sample size per year. Optional: I_t = vector of abundance index, named with years; C_t = vector of catch, named with years. 
#' @param est_sigma list of variance parameters to estimate, must match parameter names: log_sigma_R, log_sigma_C, log_sigma_I, log_CV_L, log_sigma_F
#' @param data_avail types of data included, must at least include LCX where X is the number of years of length composition data. May also include Catch or Index separated by underscore. For example, LC10, Catch_LC1, Index_Catch_LC20.
#' @param itervec number of datasets to generate in a simulation study. default=NULL for real stock assessment application. 
#' @param REML default off (FALSE)
#' @param rewrite if results already exist in the directory, should we rewrite them? TRUE or FALSE
#' @param fix_f year (by index, not actual year) to start estimating fishing mortality (e.g. year 11 out of 20 to get estimates for last 10 years); the value of F in this year will be used as the estimate and SE for all previous years. 0=estimate all years.
#' @param simulation is this a simulation? default TRUE, FALSE means you are using real data (can set itervec=NULL)
#' @param param_adjust character or vector of parameter names to change input values
#' @param val_adjust number or vector of numbers for corresponding parameter value changes
#' @param f_true default=FALSE will make starting logF values =0; change to true and will use true values from simulation
#' @useDynLib LIME

#' @return prints how many iterations were run in model directory
#' 
#' @export
run_LIME <- function(modpath, lh, input_data, est_sigma, data_avail, itervec=NULL, REML=FALSE, rewrite, fix_f, simulation=TRUE, param_adjust=FALSE, val_adjust=FALSE, f_true=FALSE){

      # dyn.load(paste0(cpp_dir, "\\", dynlib("LIME")))

  if(simulation==FALSE) iter <- 1     

for(iter in 1:length(itervec)){
    if(simulation==TRUE) iterpath <- file.path(modpath, iter)
    if(simulation==FALSE) iterpath <- modpath

    if(rewrite==FALSE){
      if(file.exists(file.path(iterpath, "Derived_quants.rds"))) next
      if(file.exists(file.path(iterpath, "NAs_final_gradient.txt"))) next
      if(file.exists(file.path(iterpath, "high_final_gradient.txt"))) next
    }

    if(rewrite==TRUE){
      if(file.exists(file.path(iterpath, "NAs_final_gradient.txt"))) unlink(file.path(iterpath, "NAs_final_gradient.txt"), TRUE)
      if(file.exists(file.path(iterpath, "high_final_gradient.txt"))) unlink(file.path(iterpath, "high_final_gradient.txt"), TRUE)
    }

    if(simulation==TRUE){
      sim <- readRDS(file.path(iterpath, "True.rds"))
      if(f_true==TRUE) f_inits <- sim$F_t
      if(f_true==FALSE) f_inits <- NULL
      input_data <- list("years"=1:sim$Nyears, "LF"=sim$LF, "I_t"=sim$I_t, "C_t"=sim$C_t, "obs_per_year"=sim$obs_per_year, "F_t"=f_inits)
    }

    ## check that inputs in right format    
    inits <- create_inputs(lh=lh, input_data=input_data, param=param_adjust, val=val_adjust)

    Nyears <- inits$Nyears 

    obs_per_yr <- inits$obs_per_year
    
    Sdreport <- NA
    ParList <- NA  
    df <- NULL
    if(f_true==TRUE) Fpen <- 0
    if(f_true==FALSE) Fpen <- 1
    if(inits$SigmaR > 0.05) SigRpen <- 0
    if(inits$SigmaR <= 0.05) SigRpen <- 1

      TmbList <- format_input(input=inits, data_avail=data_avail, Fpen=Fpen, SigRpen=SigRpen, SigRprior=c(inits$SigmaR, 0.2), est_sigma=est_sigma, REML=REML, fix_f=fix_f, f_startval=inits$F_t)

      saveRDS(TmbList, file.path(iterpath, "Inputs.rds")) 

      if(all(is.na(ParList))) ParList <- TmbList[["Parameters"]]  

      ## create objects to save best results
        obj_save <- NULL
        jnll <- NULL
        opt_save <- NULL
        opt_save[["final_gradient"]] <- NA

      ## first run
      obj <- MakeADFun(data=TmbList[["Data"]], parameters=ParList, random=TmbList[["Random"]], map=TmbList[["Map"]],inner.control=list(maxit=1e3), hessian=FALSE, DLL="LIME")

        # check_id <- Check_Identifiable(obj)
        # fix_f <- grep("Bad", check_id[which(check_id[,"Param"]=="log_F_t_input"),3])      
        # good_f <- c(1:Nyears)[which(1:Nyears %in% fix_f == FALSE)] 
        # TmbList$Map[["log_F_t_input"]] = 1:length(TmbList$Parameters[["log_F_t_input"]])
        # TmbList$Map[["log_F_t_input"]][fix_f] <- NA
        # TmbList$Map[["log_F_t_input"]] <- factor(TmbList$Map[["log_F_t_input"]])
        # if(length(fix_f)>0){
        #   TmbList$Data$fix_f <- fix_f
        #   TmbList$Data$fill_f <- good_f[length(good_f)]
        # }
      # if(bb==1) saveRDS(TmbList, file.path(iterpath, "Inputs1.1.rds"))
      # obj <- MakeADFun(data=TmbList[["Data"]], parameters=ParList, random=TmbList[["Random"]], map=TmbList[["Map"]],inner.control=list(maxit=1e3), hessian=FALSE, DLL="LIME")  


      ## Settings
      obj$env$inner.control <- c(obj$env$inner.control, "step.tol"=c(1e-8,1e-12)[1], "tol10"=c(1e-6,1e-8)[1], "grad.tol"=c(1e-8,1e-12)[1]) 
        Upr = rep(Inf, length(obj$par))
        Upr[match("log_sigma_R",names(obj$par))] = log(2)
        # Upr[match("logS95", names(obj$par))] = log(inits$AgeMax)
        Upr[match("logS50", names(obj$par))] = log(inits$AgeMax)
        Upr[which(names(obj$par)=="log_F_t_input")] = log(20)
        Upr[match("log_sigma_F", names(obj$par))] <- log(2)
        Lwr <- rep(-Inf, length(obj$par))
        Lwr[match("logS50", names(obj$par))] = log(0.1)

        ## Run optimizer
        opt <- tryCatch( nlminb( start=obj$par, objective=obj$fn, gradient=obj$gr, upper=Upr, lower=Lwr, control=list(trace=1, eval.max=1e4, iter.max=1e4, rel.tol=1e-10) ), error=function(e) NA)    
        jnll <- obj$report()$jnll   
        if(all(is.na(opt))==FALSE & is.na(jnll)==FALSE){
          opt[["final_gradient"]] = obj$gr( opt$par ) 
          opt_save <- opt
          obj_save <- obj
          jnll_save <- obj_save$report()$jnll
        }      


        ## loop to try to get opt to run
          for(i in 1:5){
            if(all(is.na(opt))){
              obj <- MakeADFun(data=TmbList[["Data"]], parameters=ParList,
                            random=TmbList[["Random"]], map=TmbList[["Map"]], 
                            inner.control=list(maxit=1e3), hessian=FALSE, DLL="LIME")
                    obj$env$inner.control <- c(obj$env$inner.control, "step.tol"=c(1e-8,1e-12)[1], "tol10"=c(1e-6,1e-8)[1], "grad.tol"=c(1e-8,1e-12)[1]) 
                opt <- tryCatch( nlminb( start= obj$env$last.par.best[-obj$env$random] + rnorm(length(obj$par),0,0.2), 
                  objective=obj$fn, gradient=obj$gr, upper=Upr, lower=Lwr, 
                  control=list(trace=1, eval.max=1e4, iter.max=1e4, rel.tol=1e-10)), error=function(e) NA)
                jnll <- obj$report()$jnll
            }
            if(all(is.na(opt))==FALSE & is.na(jnll)==FALSE){
              opt[["final_gradient"]] = obj$gr( opt$par )       
              opt_save <- opt
              obj_save <- obj
              jnll_save <- jnll
              break
            }
          }
          

        ## if opt ran: 
        if(all(is.na(opt_save))==FALSE){  

          ## check convergence -- don't let it become NA after it has had a high final gradient
          for(i in 1:2){
            if(all(is.na(opt_save[["final_gradient"]])==FALSE)){
               if(abs(min(opt_save[["final_gradient"]]))>0.01){
                obj <- MakeADFun(data=TmbList[["Data"]], parameters=ParList,
                            random=TmbList[["Random"]], map=TmbList[["Map"]], 
                            inner.control=list(maxit=1e3), hessian=FALSE, DLL="LIME")
                      obj$env$inner.control <- c(obj$env$inner.control, "step.tol"=c(1e-8,1e-12)[1], "tol10"=c(1e-6,1e-8)[1], "grad.tol"=c(1e-8,1e-12)[1]) 
                opt <- tryCatch( nlminb( start= obj$env$last.par.best[-obj$env$random] + rnorm(length(obj$par),0,0.2), 
                  objective=obj$fn, gradient=obj$gr, upper=Upr, lower=Lwr, 
                  control=list(trace=1, eval.max=1e4, iter.max=1e4, rel.tol=1e-10)), error=function(e) NA)
                jnll <- obj$report()$jnll
              }
            }
              if(all(is.na(opt))==FALSE & is.na(jnll)==FALSE){
                if(is.null(jnll_save)){
                    opt[["final_gradient"]] = obj$gr( opt$par )       
                    opt_save <- opt
                    obj_save <- obj
                    jnll_save <- jnll
                }
                if(is.null(jnll_save)==FALSE){
                    if(jnll<=jnll_save){
                        opt[["final_gradient"]] = obj$gr( opt$par )       
                        opt_save <- opt
                        obj_save <- obj
                        jnll_save <- jnll
                    }
                }
              }
            if(abs(min(opt_save[["final_gradient"]]))<=0.01) break
          }
        }
        if(all(is.na(opt_save))==FALSE)  df <- data.frame(opt_save$final_gradient, names(obj_save$par), opt_save$par, exp(opt_save$par))


        ## write error message in directory if opt wouldn't run
          if(all(is.null(opt_save))) write("NAs final gradient", file.path(iterpath, "NAs_final_gradient.txt"))
          if(all(is.null(opt_save)==FALSE)) if(abs(min(opt_save[["final_gradient"]]))>0.01) write(opt_save[["final_gradient"]], file.path(iterpath, "high_final_gradient.txt"))

        ParList <- obj_save$env$parList( x=obj_save$par, par=obj_save$env$last.par.best )
        
        ## Standard errors
        Report = tryCatch( obj_save$report(), error=function(x) NA)
        saveRDS(Report, file.path(iterpath, "Report.rds"))  

        Sdreport = tryCatch( sdreport(obj_save, bias.correct=TRUE), error=function(x) NA )
        saveRDS(Sdreport, file.path(iterpath, "Sdreport.rds"))



# FUN <- function(InputMat, log=TRUE, rel=FALSE){
#           index <- which(is.na(InputMat[,2])==FALSE)
#           if(log==TRUE) return(c( exp(InputMat[index,1]-1.96*InputMat[index,2]), rev(exp(InputMat[index,1]+1.96*InputMat[index,2]))))
#           if(log==FALSE) return(c( InputMat[index,1]-1.96*InputMat[index,2], rev(InputMat[index,1]+1.96*InputMat[index,2])))
# } 
#   plot(Report$F_t, lwd=2, col="blue", ylim=c(0, max(Report$F_t)*1.5), type="l")
#   polygon( y=FUN(summary(Sdreport)[which(rownames(summary(Sdreport))=="lF_t"),], log=TRUE), x=c(which(is.na(summary(Sdreport)[which(rownames(summary(Sdreport))=="lF_t"),2])==FALSE), rev(which(is.na(summary(Sdreport)[which(rownames(summary(Sdreport))=="lF_t"),2])==FALSE))), col=rgb(0,0,1,alpha=0.2), border=NA)


          Derived = calc_derived_quants( Obj=obj_save )
          saveRDS(Derived, file.path(iterpath, "Derived_quants.rds"))

        if(iter==1) write.csv(df, file.path(modpath, "df.csv"))  

        rm(Report)
        rm(Sdreport)
        rm(TmbList)
        rm(opt)
        rm(obj)
        rm(df)  
        rm(opt_save)
        rm(obj_save)
  }


return(paste0(max(itervec), " iterates run in ", modpath))

}