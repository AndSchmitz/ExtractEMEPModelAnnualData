# ExtractEMEPModelAnnualData

This script extracts annual values from [EMEP MSC-W model](https://acp.copernicus.org/articles/12/7825/2012/acp-12-7825-2012.html) results at user-specified point coordinates. This script has been tested for data that can be downloaded by clicking on "2000-2018 (Type2)" at [this website](https://www.emep.int/mscw/mscw_ydata.html) and then selecting files with "year" in the file name. As of 2023-03-31, these are 20 NetCDF-files (one per year in 2000-2019), each approx. 79 MB in size. This script does not change variable names or units. For an explanation of variable names and units see section "Compounds in NetCDF files" at [this website](https://www.emep.int/mscw/mscw_ydata.html).


## How to use

 - Download all files from this repository (e.g. via Code -> Download ZIP above) and unzip.

 - Download at least one .nc file with annual data from the EMEP website (see above) and place it in the "Input" folder. Do not change names of files. File names must have the extension ".nc" and the part "year.XXXX" in the file names is used to extract the year from the file name.

 - Script 01_Convert_NetCDF_to_CSV_gridded.R:

    - This scripts converts the NetCDF files to CSV (one row per combination of grid cell and variable).
    - Install all libraries listed at the top of the script. Change the variable "WorkDir" at the beginning of the script.
    - Adjust desired variables to extract. See the EMEP website linked above for a list of variables. Note that dry deposition rates are land-use specific.
    - Run the script

 - Script 02_Extract_PointData_from_gridded.R:

    - The second scripts extracts data from the CSV files at point coordinates.
    - Install all libraries listed at the top of the script. Change the variable "WorkDir" at the beginning of the script.
    - Make sure the file "PointCoords.csv" is in the "Input" folder. Coords must be standard lon/lat coords (EPSG:4326).
    - Run the script
    - Extracted data will be placed in "PointDataExtractedFromEMEPGriddedCSV.csv" in the "Output" folder.

   

## Other information

NetCDF files can also be inspected using a web view (adjust URL to switch years): https://thredds.met.no/thredds/godiva2/godiva2.html?server=https://thredds.met.no/thredds/wms/data/EMEP/2020_Reporting/EMEP01_rv4_35_year.2019met_2018emis.nc

The EMEP 0.1 x 0.1 degree grid is a standard WGS84 grid according to the "EMEP_gridding_system_documentation" found [here]( https://webdab01.umweltbundesamt.at/download/EMEP_gridding_system_documentation.pdf) and is linked to on [this website](https://emep.int/mscw/mscw_moddata.html). In this document it says: "At the 36th session of the EMEP Steering Body the EMEP Centers suggested to increase spatial resolution of reported emissions from 50x 50 km EMEP grid to 0.1° × 0.1° long-lat in a geographic coordinate system (WGS84) to improve quality of monitoring."
