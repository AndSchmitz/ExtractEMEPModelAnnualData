#Extracts data from EMEP netcdf format to CSV.
#Each year and variable are extracted separately to avoid memory problems.

#init-----
rm(list=ls())
graphics.off()
options(warnPartialMatchDollar = T)

library(ncdf4)
library(stringr)
library(dplyr)
library(data.table) #for fast writing large CSV via fwrite()

#Set working directory
WorkDir <- "/path/to/WorkDir"

#One year for all 49 EMEP variables results in a 2GB CSV file.
#Thus, define which variables to extract.
#For a list of all variables, see https://emep.int/mscw/mscw_moddata.html
TargetVars <- c(
  "DDEP_OXN_m2Conif", #Dry deposition of oxidized nitrogen per m2 Coniferous Forest
  "DDEP_OXN_m2Decid", #Dry deposition of oxidized nitrogen per m2 Decidous Forest
  "DDEP_RDN_m2Conif", #Dry deposition of reduced nitrogen per m2 Coniferous Forest
  "DDEP_RDN_m2Decid", #Dry deposition of reduced nitrogen per m2 Decidous Forest
  "WDEP_RDN", #Wet deposition of reduced nitrogen
  "WDEP_OXN" #Wet deposition of oxidized nitrogen
)


#------ no changes required below this point----------

#Prepare I/O
InDir <- file.path(WorkDir,"Input")
OutDir <- file.path(WorkDir,"Output")
dir.create(OutDir,showWarnings = F)

#Extract data-----
EMEPFiles <- list.files(
  path = file.path(InDir),
  pattern = "*.nc",
  full.names = T
)
if ( length(EMEPFiles) == 0 ) {
  stop(paste("No .nc files found in folder:", InDir))
}

#Loop over all .nc files in input folder
for ( CurrentFile in EMEPFiles ) {
  EMEPDataCurrentYear <- data.frame()
  CurrentYear <- gsub(x = CurrentFile, pattern = ".*year\\.", replacement = "")
  CurrentYear <- as.numeric(str_sub(string = CurrentYear, start = 1, end = 4))
  # open a NetCDF file
  ncin <- nc_open(CurrentFile)
  #Loop over variables. Extract if variable is in list of desired variables  
  Vars <- names(ncin$var)
  for  ( CurrentVar in Vars ) {
    if ( !(CurrentVar %in% TargetVars) ) next
    print(paste("Extracting data for variable",CurrentVar,"in file",basename(CurrentFile)))
    CurrentDat <- ncvar_get(ncin, CurrentVar)
    #Extract coords. These are the *grid cell centers*. This is documented in the excel files
    #that can be downloaded here: https://www.ceip.at/the-emep-grid/grid-definiton
    #There it says: "longitude/latitude	center of a 0.1°x0.1° cell in degrees"    
    Lon <- as.numeric(ncvar_get(ncin, "lon"))
    Lat <- as.numeric(ncvar_get(ncin, "lat"))
    CurrentUnit <- ncin$var[[CurrentVar]]$units
    CurrentUnit <- gsub(x = CurrentUnit, pattern = "/", replacement = "_per_")
    LonLat <- expand.grid(Lon, Lat)
    tmp.vec <- as.vector(CurrentDat)
    CurrentDatDF <- data.frame(cbind(LonLat, tmp.vec))
    colnames(CurrentDatDF) <- c("GridCellCenterLonDeg","GridCellCenterLatDeg","Value")
    CurrentDatDF <- CurrentDatDF %>%
      mutate(
        Variable = CurrentVar,
        Year = CurrentYear,
        Unit = CurrentUnit
      )
    EMEPDataCurrentYear <- bind_rows(EMEPDataCurrentYear,CurrentDatDF)
  
  } #end of loop over variables for current file
  
  nc_close(ncin)
  
  #Save data for current year-----
  print(paste("Writing CSV for year", CurrentYear, "..."))
  fwrite(
    x = EMEPDataCurrentYear,
    file = file.path(OutDir,paste0("EMEPData_",CurrentYear,".csv")),
    sep = ";"
  )

} #end of loop over files

print("Done.")