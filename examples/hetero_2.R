setwd("./R")

source("metrics.R")
source("help_functions.R")
source('crf_km.R')

list.of.packages <- c("ggplot2", "grf", "quantregForest", "randomForestSRC", "survival")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos='http://cran.us.r-project.org')

library(ggplot2)
library(quantregForest)
library(randomForestSRC)
library(survival)
library(grf)

# ------------------------------------------------------- #

attach(mtcars)
op <- par(mfrow=c(1,1), mar=c(2,2,1,1)+0.1, oma = c(0,0,0,0) + 0.1, pty="s")

# Create the data
n <- 1000
n_test <- 200
p <- 5

# training data
Xtrain <- matrix(runif(n = n*p, min = -1, max = 1), nrow = n, ncol = p)
Ttrain <- 10 + rnorm(n = n, mean = 1*(Xtrain[,1]>0), sd = 1)
#ctrain <- rep(1000000000, n)
ctrain <- 10 + rexp(n = n, rate = 0.05) - 2
Ytrain <- pmin(Ttrain, ctrain)
censorInd <- 1*(Ttrain <= ctrain)
data_train <- cbind.data.frame(Xtrain, Ytrain, censorInd)
# plot training data
#plot(Xtrain[,1], Ytrain, cex = 0.2)
#points(Xtrain[!censorInd,1], Ytrain[!censorInd], type = 'p', col = 'red', cex = 0.3)
#points(Xtrain[!censorInd,1], Ttrain[!censorInd], type = 'p', col = 'green', cex = 0.3)

# test data
Xtest <- matrix(runif(n = n_test*p, min = -1, max = 1), nrow = n_test, ncol = p)
Ytest <- 10 + rnorm(n = n_test, mean = 1*(Xtest[,1]>0), sd = 1)
data_test <- cbind.data.frame(Xtest, Ytest, rep(1, n_test))
plot(Xtest[,1], Ytest, cex = 0.04, xlab = 'x', ylab = 'y', ylim = c(7, 14))

# column names
xnam <- paste0('x', 1:p)
colnames(data_train) <- c(xnam, 'y', 'status')
colnames(data_test) <- c(xnam, 'y', 'status')

# parameters
ntree = 2000
taus <- c(0.1, 0.5, 0.9)
nodesize.crf <- 100
nodesize.qrf <- 100
nodesize.grf <- 100
nodesize.rsf <- 100

one_run = function(ntree, tau, nodesize) {
  # build censored Extreme Forest model
  fmla <- as.formula(paste("y ~ ", paste(xnam, collapse= "+")))
  Yc <- crf.km(fmla, ntree = ntree, nodesize = nodesize.crf, data_train = data_train, data_test = data_test, 
               yname = 'y', iname = 'status', tau = tau, method = "grf", calibrate_taus = taus)
  Yc <- Yc$predicted
  
  Yc.qrf <- crf.km(fmla, ntree = ntree, nodesize = nodesize.crf, data_train = data_train, data_test = data_test, 
                   yname = 'y', iname = 'status', tau = tau, method = "ranger")
  Yc.qrf <- Yc.qrf$predicted
  
  # generalized random forest (Stefan's)
  # grf_qf_latent <- quantile_forest(data_train[,1:p,drop=FALSE], Ttrain, quantiles = tau, 
  # num.trees = ntree, min.node.size = nodesize)
  # Ygrf_latent <- predict(grf_qf_latent, data_test[,1:p,drop=FALSE], quantiles = tau)
  
  grf_qf <- quantile_forest(data_train[,1:p,drop=FALSE], Ytrain, quantiles = tau, 
                            num.trees = ntree, min.node.size = nodesize.grf)
  Ygrf <- predict(grf_qf, data_test[,1:p,drop=FALSE], quantiles = tau)
  
  # quantile random forest (Meinshasen)
  # qrf_latent <- quantregForest(x=Xtrain, y=Ttrain, nodesize=nodesize, ntree=ntree)
  # Yqrf_latent <- predict(qrf_latent, Xtest, what = tau)
  
  qrf <- quantile_forest(data_train[,1:p,drop=FALSE], Ytrain, quantiles = tau, 
                         num.trees = ntree, min.node.size = nodesize.qrf, regression.splitting = TRUE)
  Yqrf <- predict(qrf, data_test[,1:p,drop=FALSE], quantiles = tau)
  
  # RSF
  v.rsf <- rfsrc(Surv(y, status) ~ ., data = data_train, ntree = ntree, nodesize = nodesize.rsf)
  surv.rsf <- predict(v.rsf, newdata = data_test)
  Ysurv <- find_quantile(surv = surv.rsf, max_value = max(data_train$y), tau = tau)
  
  # comparison
  Xsort <- sort(Xtest[,1], index.return=TRUE)
  X1 <- Xsort$x
  Xindex <- Xsort$ix
  quantiles <- 10 + qnorm(tau, 1*(X1>0), 1)
  lines(X1, quantiles, col = 'black', cex = 2)
  lines(X1, Ygrf[Xindex], col = 'blue', lty = 5, cex = 1)
  # lines(Xtest[,1], Ygrf_latent, col = 'black', type = 'b', pch = 18, lty = 1, cex = .5)
  lines(X1, Yqrf[Xindex], col = 'cyan', lty = 5, cex = 1)
  lines(X1, Yc[Xindex], col='red', lty = 5, cex = 1)
  lines(X1, Yc.qrf[Xindex], col='purple', lty = 5, cex = 1)
  lines(X1, Ysurv[Xindex], col='green', lty = 5, cex = 1)
}

for (tau in taus){
  one_run(ntree, tau, nodesize)
}

# Add a legend
legend(-1, 14, legend=c("true quantile", "crf-generalized", "crf-quantile", "grf", "qrf", "rsf"),
       lty=c(1, 5, 5, 5, 5, 5), cex=1.1, pch = c(-1,-1, -1, -1, -1, -1), 
       col = c('black', 'red', 'purple', 'blue', 'cyan', 'green'))
