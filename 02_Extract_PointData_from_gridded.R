#Takes gridded EMEP data in CSV format produced by step "01_Convert_NetCDF_to_CSV_gridded"
#and extracts data for specific points

#init-----
rm(list=ls())
graphics.off()
options(warnPartialMatchDollar = T)

library(data.table) #for fast I/O via fread(), fwrite()
library(dplyr)
library(geosphere) #For calculating spatial distances
library(ggplot2)


#Set working directory
WorkDir <- "/path/to/WorkDir"


#------ no changes required below this point----------

#Prepare I/O
InDir <- file.path(WorkDir,"Input")
OutDir <- file.path(WorkDir,"Output")
dir.create(OutDir,showWarnings = F)

#Prepare coords for points to extract----
CoordsFile <- file.path(InDir,"PointCoords.csv")
if ( !file.exists(CoordsFile) ) {
  stop(paste("Expected coordinates file to exist:", CoordsFile))  
}
PointCoords <- read.table(
  file = CoordsFile,
  header = T,
  sep = ";",
  dec = ",",
  stringsAsFactors = F
) 
ColsRequired <- c("LocationLabel", "Lat_EPSG4326", "Lon_EPSG4326")
MissCols <- ColsRequired[!(ColsRequired %in% colnames(PointCoords))]
if ( length(MissCols) > 0 ) {
  stop(paste("Coordinates file missing the following columns:", paste(MissCols, collapse = ",")))
}

PointCoords <- PointCoords %>%
  select(LocationLabel, Lat_EPSG4326, Lon_EPSG4326) %>%
  filter(
    (!is.na(LocationLabel)) &
    (!is.na(Lat_EPSG4326)) &
    (!is.na(Lon_EPSG4326))
  ) %>%
  # drop_na() %>% #no coords for 1209
  mutate(
    Lat_EPSG4326 = as.numeric(Lat_EPSG4326),
    Lon_EPSG4326 = as.numeric(Lon_EPSG4326)
  ) %>%
  distinct()

#Check for duplicates
PointCoords <- PointCoords %>%
  distinct()
Dups <- PointCoords %>%
  group_by(LocationLabel) %>%
  mutate(
    nRows = n()
  ) %>%
  ungroup() %>%
  filter(
    nRows != 1
  )
if ( nrow(Dups) != 0 ) {
  stop("Multiple rows with different coords for the same LocationLabel in data")
}



#Find EMEP grid cell for each point to extract once------

print("Finding EMEP grid cell for each LocationLabel from PointCoords.csv...")

#List of EMEP gridded CSV files
GridFiles <- list.files(
  path = OutDir,
  full.names = T,
  pattern = "^EMEPData.*.csv$"
)
if ( length(GridFiles) == 0 ) {
  stop(paste("No .csv files starting with \"EMEPData\" found in folder", OutDir))
}

#Read first file to establish relation between point coords and corresponding grid cells
EMEPCoords <- fread(
  file = GridFiles[1]
) 
ColsRequired <- c("GridCellCenterLonDeg", "GridCellCenterLatDeg", "Value", "Variable", "Year", "Unit")
MissCols <- ColsRequired[!(ColsRequired %in% colnames(EMEPCoords))]
if ( length(MissCols) > 0 ) {
  stop(paste("Gridded EMEPCoords CSV files missing the following columns:", paste(MissCols, collapse = ",")))
}

EMEPCoords <- EMEPCoords %>%
  select(GridCellCenterLatDeg, GridCellCenterLonDeg) %>%
  distinct()
PointCoords <- PointCoords %>%
  mutate(
    EMEPGridCellCenterLon = NA,
    EMEPGridCellCenterLat = NA
  )
for ( i in 1:nrow(PointCoords) ) {
  #For each point in PointCoords, find the EMEP grid cell which has the smallest distance
  #from its center coordinates to the point.
  #Reduce the number of potential candidate grid cells to speed up calculations.
  #We are on a 0.1 x 0.1 degree grid, so the best matching grid cell should
  #definitely have its center within a radius of +-0.5 degree around the 
  #plot center.
  EMEPCoordsCandidates <- EMEPCoords %>%
    filter(
      GridCellCenterLonDeg > (PointCoords$Lon_EPSG4326[i] - 0.5),
      GridCellCenterLonDeg < (PointCoords$Lon_EPSG4326[i] + 0.5),
      GridCellCenterLatDeg > (PointCoords$Lat_EPSG4326[i] - 0.5),
      GridCellCenterLatDeg < (PointCoords$Lat_EPSG4326[i] + 0.5)      
    )
  #Calculate distance from the point coordinate to each EMEP grid cell center
  #considering actual distances on earth
  DistVec <- distm(
    x = EMEPCoordsCandidates[,c("GridCellCenterLonDeg","GridCellCenterLatDeg")],
    y = c(PointCoords$Lon_EPSG4326[i], PointCoords$Lat_EPSG4326[i]),
    fun = distHaversine
  )
  #Identify the closest EMEP grid cell center
  idx_MinDist <- which( DistVec == min(DistVec) )
  if ( length(idx_MinDist) != 1 ) {
    stop("Could not find a single unique EMEP grid cell for a specific point")
  }
  PointCoords$EMEPGridCellCenterLon[i] <- EMEPCoordsCandidates$GridCellCenterLonDeg[idx_MinDist]
  PointCoords$EMEPGridCellCenterLat[i] <- EMEPCoordsCandidates$GridCellCenterLatDeg[idx_MinDist]
}


#Extract from EMEP files-----
print("Extracting data...")
PointData <- data.frame()
for ( CurrentFile in GridFiles ) {
  print(paste("Reading file",basename(CurrentFile)))
  CurrentDat <- fread(
    file = CurrentFile
  )
  CurrentYear <- unique(CurrentDat$Year)
  if ( length(CurrentYear) != 1 ) {
    stop("Expecting data from exactly one year per EMEP gridded CVS file")
  }
  for ( CurrentVar in unique(CurrentDat$Variable) ) {
    Sub <- CurrentDat %>%
      filter(
        Variable == CurrentVar
      )
    CurrentUnit <- unique(Sub$Unit)
    if ( length(CurrentUnit) != 1 ) {
      stop("Expecting data in exactly one unit per variable")
    }
    tmp <- PointCoords %>%
      mutate(
        Variable = CurrentVar,
        Unit = CurrentUnit,
        Year = CurrentYear,
        Value = NA
      )
    for ( i in 1:nrow(tmp) ) {
      TargetEMEPCellLonDeg <- tmp$EMEPGridCellCenterLon[i]
      TargetEMEPCellLatDeg <- tmp$EMEPGridCellCenterLat[i]
      
      #Find corresponding EMEP grid cell and sanity check it exists
      idx_EMEP <- which(
        (Sub$GridCellCenterLonDeg == TargetEMEPCellLonDeg) &
        (Sub$GridCellCenterLatDeg == TargetEMEPCellLatDeg)
      )
      if ( length(idx_EMEP) != 1 ) {
        stop("Could not find EMEP grid cell for current point data point")
      }
      tmp$Value[i] <- Sub$Value[idx_EMEP]
    } #end of loop over point data points
    PointData <- bind_rows(PointData,tmp)
    
    
    #Plot data for quick visual checking-----
    PlotDatGrid <- Sub 
    LargeCities <- maps::world.cities %>%
      filter(
        pop > 1e6
      )
    
    CountryBorders <- map_data("world")
    ggplot() +
      geom_tile(
        data = PlotDatGrid,
        mapping = aes(
          x = GridCellCenterLonDeg,
          y = GridCellCenterLatDeg,
          fill = Value
        )        
      ) +
      geom_point(
        data = tmp,
        mapping = aes(
          x = Lon_EPSG4326,
          y = Lat_EPSG4326,
          color = Value
        ),
        colour = "red",
        pch = 1,
        size = 2
      ) +
      geom_polygon(
        data = CountryBorders,
        aes(
          x = long,
          y = lat,
          group = group
        ),
        fill = NA,
        color = "black"
      ) +
      xlab("") +
      ylab("") +
      ggtitle(paste(CurrentVar,CurrentYear,CurrentUnit)) +
      theme_minimal() +
      theme(
        axis.ticks = element_blank(),
        axis.text = element_blank()
      ) +
      coord_sf(
        xlim=c(min(tmp$Lon_EPSG4326) - 10, max(tmp$Lon_EPSG4326) + 10),
        ylim=c(min(tmp$Lat_EPSG4326) - 10, max(tmp$Lat_EPSG4326) + 10)
      ) +
      geom_point(
        data = LargeCities,
        color = "black",
        pch = 1,
        aes(
          x = long,
          y = lat,
          group = NULL
        )
      )  
    
    ggsave(
       filename = file.path(OutDir,paste0(CurrentVar,"_",CurrentYear,".png"))
     )
    
  
  } #end of loop over variables
} #end of loop over files

#Save-----
print("Writing results...")

write.table(
  x = PointData,
  file = file.path(OutDir,"PointDataExtractedFromEMEPGriddedCSV.csv"),
  sep = ";",
  row.names = F
)

print("Done.")