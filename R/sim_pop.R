#' Operating model
#'
#' \code{sim_pop} Age-converted-to-length-based operating model specifying true population dynamics
#'
#' @param lh list of life history information, from create_lh_list
#' @param Nyears number of years to simulate
#' @param Fdynamics Specify name of pattern of fishing mortality dynamics, Constant, Endogenous, Ramp, Increasing, or None
#' @param Rdynamics Specify name of pattern of recruitment dynamics, Constant, Pulsed, Pulsed_up, or BH
#' @param Nyears_comp number of years of length composition data
#' @param comp_sample vector with sample sizes of length composition data annually
#' @param nburn number of years of burn-in for operating model
#' @param seed set seed for generating stochastic time series
#' @param modname save model name for true dynamics in named list output

#' @return named list of attributes of true population/data
#' @export
sim_pop <- function(lh, Nyears, Fdynamics, Rdynamics, Nyears_comp, comp_sample, nburn, seed, modname){

    ## SB_t = spawning biomass over time
    ## F_t = fishing mortality over time
    ## Cn_at = number of individuals that die from fishing mortality
    ## N_at = abundance by number at age over time

    with(lh, {
    ##########################
    ## Initial calcs
    ##########################

    tyears <- nburn+Nyears


    ##########################
    ## Random variables
    ##########################
    set.seed(seed)
    RecDev <- rnorm(tyears, mean=0, sd=SigmaR)
    FishDev <- rnorm(tyears, mean=0, sd=SigmaF)
    IndexDev <- rnorm(tyears, mean=0, sd=SigmaI)
    CatchDev <- rnorm(tyears, mean=0, sd=SigmaC)

    ##########################
    ## Data objects
    ##########################
    TB_t <- VB_t <- SB_t <- F_t <- R_t <- rep(NA, tyears)                               
    Cn_at <- N_at <- matrix(NA, nrow=length(L_a), ncol=tyears)

    #####################################
    ## Fishing and recruitment dynamics
    #####################################   

    if(Fdynamics=="Ramp") Framp_t <- c(rep(F1, nburn), "rampup"=seq(F1, Fmax, length=floor(Nyears/2)), 
        "peak"=rep(Fmax, floor((Nyears-floor(Nyears/2))/2)), 
        "managed"=rep(Fmax/3, Nyears-floor(Nyears/2)-floor((Nyears-floor(Nyears/2))/2)))
    if(Fdynamics=="Constant") Fconstant_t <- c(rep(F1, nburn), rep(Fequil, Nyears))
    if(Fdynamics=="Increasing") Finc_t <- c(rep(F1, nburn), seq(F1, Fmax, length=Nyears))
    if(Fdynamics=="None") F_t <- rep(0, tyears)

    if(Rdynamics=="Pulsed") Rpulse_t <- c(rep(R0, nburn), "initial"=rep(R0, floor(Nyears/3)),
        "pulse_down"=rep(R0/3, floor(Nyears/3)), "pulse_up"=rep(R0, Nyears-floor(Nyears/3)))
    if(Rdynamics=="Pulsed_up") Rpulse_t <- c(rep(R0, nburn), "initial"=rep(R0, floor(Nyears/3)), "pulse_up"=rep(R0*3, floor(Nyears/3)), "pulse_down"=rep(R0, Nyears-floor(Nyears/3)))
    if(Rdynamics=="Constant") Rconstant_t <- rep(R0, tyears)

        if(Fdynamics=="Ramp"){
            F_t <- Framp_t * exp(FishDev - (SigmaF^2)/2)
        }
        if(Fdynamics=="Constant"){
            F_t <- Fconstant_t * exp(FishDev - (SigmaF^2)/2)
        }
        if(Fdynamics=="Increasing"){
            F_t <- Finc_t * exp(FishDev - (SigmaF^2)/2)
        }
        if(Fdynamics=="Endogenous"){
            F_t[1] <- F1
        }
        if(Rdynamics=="Constant"){
            R_t <- Rconstant_t * exp(RecDev - (SigmaR^2)/2)
        }
        if(Rdynamics=="Pulsed"){
            R_t <- Rpulse_t * exp(RecDev - (SigmaR^2)/2)
        }
        if(Rdynamics=="Pulsed_up"){
            R_t <- Rpulse_t * exp(RecDev - (SigmaR^2)/2)
        }
        if(Rdynamics=="BH"){
            R_t[1] <- R0 * exp(RecDev[1] - (SigmaR^2)/2)
        }

    ## year 1
    for(a in 1:length(L_a)){
        if(a==1){
            N_at[a,1] <- R_t[1]
        }
        if(a>1 & a<length(L_a)){
            N_at[a,1] <- N_at[a-1,1] * exp(-M - F_t[1] * S_a[a-1])
        }
        if(a==length(L_a)){
            N_at[a,1] <- (N_at[a-1,1] * exp(-M - F_t[1] * S_a[a])) / (1-exp(-M - F_t[1] * S_a[a]))
        }

    }
    VB_t[1] <- sum(N_at[,1] * W_a * S_a)
    TB_t[1] <- sum(N_at[,1] * W_a)
    SB_t[1] <- sum(N_at[,1] * W_a * Mat_a)
    Cn_at[,1] <- N_at[,1] * (1 - exp(-M - F_t[1] * S_a)) * (F_t[1] *S_a)/(M + F_t[1] * S_a)

    ##########################
    ## Projection
    ##########################
    Na0 <- rep(NA, length(W_a))
        if(Rdynamics=="Pulsed"){
            R0 <- median(Rpulse_t[-c(1:nburn)])
        }
    Na0[1] <- R0
    for(a in 2:length(W_a)){
        Na0[a] <- R0 * exp(-M*(a-1))
    }
    SB0 <- sum(Na0*Mat_a*W_a)

    for(y in 2:tyears){
        ## fishing effort and recruitment, not dependent on age structure
        if(Fdynamics=="Endogenous"){
            if(y <= nburn) F_t[y] <- F1
            if(y > nburn) F_t[y] <- F_t[y-1]*(SB_t[y-1]/(Fequil*SB0))^Frate * exp(FishDev[y] - (SigmaF^2)/2)
        }
        if(Rdynamics=="BH"){
            if(h==1) h_use <- 0.7
            if(h!=1) h_use <- h
            R_t[y] <- (4 * h_use * R0 * SB_t[y-1] / ( SB0*(1-h_use) + SB_t[y-1] * (5*h_use-1))) * exp(RecDev[y] - (SigmaR^2)/2)
        }

        ## age-structured dynamics
        for(a in 1:length(L_a)){

            if(a==1){
                N_at[a,y] <- R_t[y]
            }
            if(a>1 & a<length(L_a)){
                N_at[a,y] <- N_at[a-1,y-1] * exp(-M - F_t[y-1] * S_a[a-1])
            }
            if(a==length(L_a)){
                N_at[a,y] <- (N_at[a-1,y-1] * exp(-M - F_t[y-1] * S_a[a-1])) + (N_at[a,y-1] * exp(-M - F_t[y-1] * S_a[a]))
            }

            ## spawning biomass
            SB_t[y] <- sum((N_at[,y] * W_a * Mat_a))
            VB_t[y] <- sum(N_at[,y] * W_a * S_a)
            TB_t[y] <- sum(N_at[,y] * W_a)

            ## catch
            Cn_at[,y] <- N_at[,y] * (1 - exp(-M - F_t[y] * S_a)) * (F_t[y] * S_a)/ (M + F_t[y] * S_a)


        }
    }
    Cn_t <- colSums(Cn_at)
    Cw_t <- colSums(Cn_at * W_a)
    N_t <- colSums(N_at[-1,])
    D_t <- SB_t/SB0

    I_t <- qcoef * TB_t #* exp(IndexDev - (SigmaI^2)/2)
    C_t <- Cn_t #* exp(CatchDev - (SigmaC^2)/2)

    ## age to length comp
    obs_per_year <- rep(comp_sample, tyears)
    LFinfo <- AgeToLengthComp(lh=lh, tyears=tyears, N_at=N_at, comp_sample=obs_per_year)

    plba <- LFinfo$plba
    plb <- LFinfo$plb
    page <- LFinfo$page
    LF <- LFinfo$LF

    ########################################################
    ## Expected mean length in catch 
    ########################################################
    ML_t <- vector(length=tyears)
    for(y in 1:tyears){
        vul_pop <- sum(N_at[,y]*S_a)
        vul_lengths <- sum(vul_pop*plb[y,]*mids)
        ML_t[y] <- vul_lengths/vul_pop
    }

    ########################################################
    ## cut out burn-in
    ########################################################

    I_tout <- I_t[-c(1:nburn)]
    C_tout <- C_t[-c(1:nburn)]
    Cw_tout <- Cw_t[-c(1:nburn)]
            names(C_tout) <- names(Cw_tout) <- names(I_tout) <- 1:Nyears

    LFout <- LF[-c(1:nburn),]
        rownames(LFout) <- 1:Nyears

    R_tout <- R_t[-c(1:nburn)]
    N_tout <- N_t[-c(1:nburn)]
    SB_tout <- SB_t[-c(1:nburn)]
    TB_tout <- TB_t[-c(1:nburn)]
    VB_tout <- VB_t[-c(1:nburn)]
    D_tout <- D_t[-c(1:nburn)]
    F_tout <- F_t[-c(1:nburn)]
    ML_tout <- ML_t[-c(1:nburn)]
    N_atout <- N_at[,-c(1:nburn)]

        LFindex <- (Nyears-Nyears_comp+1):Nyears
        LFout <- LFout[LFindex,]
        if(is.vector(LFout)==FALSE) colnames(LFout) <- highs
        if(is.vector(LFout)){
            LFout <- t(as.matrix(LFout))
            rownames(LFout) <- (Nyears-Nyears_comp+1):Nyears
        }

    ## static SPR
    SPR_t <- sapply(1:length(F_tout), function(x) calc_ref(Mat_a=Mat_a, W_a=W_a, M=M, S_a=S_a, F=F_tout[x]))
    SPR <- SPR_t[length(SPR_t)]

    ## outputs
    lh$I_t <- I_tout
    lh$C_t <- C_tout
    lh$Cw_t <- Cw_tout
    lh$DataScenario <- modname
    lh$LF <- LFout
    lh$R_t <- R_tout
    lh$N_t <- N_tout
    lh$SB_t <- SB_tout
    lh$D_t <- D_tout
    lh$F_t <- F_tout
    lh$ML_t <- ML_tout
    lh$N_at <- N_atout
    lh$plb <- plb
    lh$plba <- plba
    lh$page <- page
    lh$SPR <- SPR
    lh$SPR_t <- SPR_t
    lh$VB_t <- VB_tout
    lh$TB_t <- TB_tout
    lh$nlbins <- length(mids)
    lh$Nyears <- Nyears
    lh$years <- 1:Nyears
    lh$obs_per_year <- obs_per_year

    return(lh)

}) ## end with function

}