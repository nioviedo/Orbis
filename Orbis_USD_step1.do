********************************************************************************
*** Treat Orbis data in USD
********************************************************************************
*** Main inputs: Industry-Global_financials_and_ratios-USD.txt
*** Additional inputs: country_list.xlsx
*** Output: Finan_`coun_loop'.dta
*** Author: Andres Blanco
*** Original: 07/16/2021
*** Code: This code departs from original .txt and save the data in dta files by country
********************************************************************************
*** Set up
********************************************************************************
cls
query memory
set more off

********************
*User Settings
********************
*User: andres
*global who = "A" 

*User: Isaac
//global who = "I" 

*User: Nicolas
global who = "N" 


********************************************************************************	
* -------------         Paths and Logs            ------------------------------
********************************************************************************

if "$who" == "A"  {
		global pathinit "/Users/jablanco/Dropbox (University of Michigan)/papers_new/LumpyTaxes/EmpiricalAnalysis"
		global pathdata_raw "/Volumes/Andres data/Orbitz data"
} 

if "$who" == "N"  {
		global pathinit "D:\Data"
 		global pathdata_raw "D:\Data\inputs\microdata\amadeus"
}
* These (sub)directories need to exist beforehand

if "$who" == "A"  {
global input_data    = "$pathinit/input"
cap mkdir 			 "$pathinit/output"
global output_data   = "$pathinit/output"
cap mkdir 			 "$pathinit/figures"
global figures       = "$pathinit/figures"
cap mkdir 			 "$pathinit/tables"
global tables        = "$pathinit/tables"
cap mkdir 			 "$pathinit/temp"
global temp          = "$pathinit/temp"
global do_files      = "$pathinit/Codes_do"
}

if "$who" == "N"  {
global input_data "$pathinit\inputs\microdata\amadeus\step1"
global output_data "$pathinit/outputs"
global figures "$pathinit/figures"
global temp "$pathinit/temp"
}

capture log close
log using "$temp/Finan_USD_Orbis.txt", replace text
*stop

********************************************************************************	
*** Country list
********************************************************************************
/*
* Import names as .txt and save as .dta
* Data number of rows:
import delimited "$pathdata_raw/Industry-Global_financials_and_ratios-USD.txt", varnames(1) encoding(UTF-8) colrange(:1) clear 
save "$pathdata_raw/step1/bvd_id_USD.dta", replace


* upload bvd id and save list with positions
use "$pathdata_raw/step1/bvd_id_USD.dta", clear
gen country= substr(bvdidnumber,1,2)
gen place  =_n
replace place  =.     if country==country[_n-1] 
drop if place==.
rename  place place_first
gen    place_last = place_first[_n+1]-1
replace place_last=431724032 if place_last==. & country=="ZW"
save "$pathdata_raw/step1/country_list_USD.dta", replace

* complete countries with countries full names
*import excel "$input_data/excel/country_list.xlsx", sheet("Sheet1") clear 
import excel "D:\Data\inputs\microdata\amadeus\excel\country_list.xlsx", sheet("Sheet1") clear 
rename A country_name
rename B country 
drop C D 
merge 1:1 country using "$pathdata_raw/step1/country_list_USD.dta"
drop if country=="CC" |  country=="CH" | country=="FK" | country=="FM" | country=="FO" 
drop if country=="GF" |  country=="GG" | country=="HT" | country=="IO" | country=="KI" 
drop if country=="KP" |  country=="MF" | country=="MO" | country=="MP" | country=="MQ" 
drop if country=="MS" |  country=="MV" | country=="PM" | country=="PN" | country=="PR" 
drop if country=="AQ" |  country=="AS" | country=="AX" | country=="BL" | country=="BQ" 
drop if country=="CK" |  country=="CX" | country=="EH" | country=="GL" | country=="GP" 
drop if country=="GS" |  country=="GU" | country=="HM" | country=="NC" | country=="NE" 
drop if country=="NF" |  country=="NR" | country=="NU" | country=="PF" | country=="PW" 
drop if country=="RE" |  country=="SB" | country=="SH" | country=="SJ" | country=="SM" 
drop if country=="TO" |  country=="TK" | country=="SX" | country=="TF" | country=="SR" 
drop if country=="IM" |  country=="JE" | country=="TC" | country=="TV" | country=="UM"    
drop if country=="VI" |  country=="VU" | country=="WF" | country=="YT" | country=="VA"   
drop if country=="UM" |  country=="TV" | country=="TL" | country=="TC" | country=="IM"   
drop _merge
sort place_first
save "$pathdata_raw/step1/country_list_name_USD.dta", replace
 
*levelsof country, local(mymakes)
*/
********************************************************************************	
*** Country .dta
********************************************************************************
* Save the data from .txt to .dta

local country_list = " BA BE BG BY CY CZ DK FI FR GB GE GI HR HU IE IS IT LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SK UA"

*local country_list = "AT AU BE CA CL CO CR CZ DK EE FI FR DE GR HU IS IE IL IT JP KR LT LU LV ME NL NZ NO PL PT SI SK ES SE TR GB US UY  RU AR IN  BR CN" 
*local country_list = "FR DE GR HU IS IE IL IT JP KR LT LU LV ME NL NZ NO PL PT SI SK ES SE TR GB US UY  RU AR IN  BR CN" 
 
	
foreach coun_loop of local country_list{
	
	* load the lines in the .txt file for each country 
	*qui use "$pathdata_raw/LC/step1/country_list.dta", clear
	 qui use "$input_data/country_list_USD.dta", clear
	
	display("`coun_loop'")

	qui sum place_first if country=="`coun_loop'"
	global data_fl=`r(mean)'-100
	qui sum place_last if country=="`coun_loop'"
	global data_ll=`r(mean)'+100
	 
	* import data for that country
	*qui import delimited "$pathdata_raw/raw_data/Industry-Global_financials_and_ratios.txt", varnames(1) encoding(UTF-8) rowrange($data_fl:$data_ll) clear
	qui import delimited "$pathdata_raw/Industry-Global_financials_and_ratios-USD.txt", varnames(1) encoding(UTF-8) rowrange($data_fl:$data_ll) clear
	
	gen country= substr(bvdidnumber,1,2) 
	keep if country=="`coun_loop'"
	
	
	compress 
	*qui save "$pathdata_raw/LC/step1/countries/Finan_`coun_loop'.dta", replace
	save "$input_data/countries/Finan_`coun_loop'_USD.dta", replace
	
}

*stop
* Clean each country

local country_list = "BA BE BG BY CY CZ DK FI FR GB GE GI HR HU IE IS IT LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SK UA"
*local country_list = "AT AU BE CA CL CO CR CZ DK EE FI FR DE GR HU IS IE IL IT JP KR LT LU LV ME NL NZ NO PL PT SI SK ES SE TR GB US UY  RU AR IN  BR CN" 

foreach coun_loop of local country_list{

display("`coun_loop'")
	
*use "$pathdata_raw/LC/step1/countries/Finan_`coun_loop'.dta", clear
use "$input_data/countries/Finan_`coun_loop'_USD.dta", replace
 
* first drop: do not use estimated number of worker/operating revenuw
drop if estimatedoperatingrevenue=="Yes" |  estimatedemployees=="Yes"
drop estimatedoperatingrevenue estimatedemployees
	
destring costsofemployees,replace force
destring addedvalue, replace force
* some of this variables has range: 1000 to 4000
destring operatingrevenueoriginalrangeval,replace force
* some of this variables has range: 1 to 4
destring employeesoriginalrangevalue, replace force

drop if consolidationcode=="LF" // Drop companies with limited financial information
drop if consolidationcode=="NF" // Drop companies with no financial information at all
    
egen id = group(bvdidnumber)
drop bvdidnumber

order id country consolidationcode filingtype closingdate numberofmonths auditstatus accountingpractice sourceforpubliclyquotedcompanies originalunits originalcurrency

* drop all ratios ratios from original data
drop  currentratiox liquidityratiox shareholdersliquidityratiox solvencyratioassetbased solvencyratioliabilitybased gearing profitperemployeeth operatingrevenueperemployeeth costsofemployeesoperatingrevenue averagecostofemployeeth shareholdersfundsperemployeeth workingcapitalperemployeeth totalassetsperemployeeth operatingrevenueoriginalrangeval employeesoriginalrangevalue
  
drop ebitdamargin ebitmargin cashflowoperatingrevenue enterprisevalueebitdax marketcapcashflowfromoperationsx netassetsturnoverx interestcoverx stockturnoverx collectionperioddays creditperioddays exportrevenueoperatingrevenue rdexpensesoperatingrevenue

drop grossmargin profitmargin roeusingplbeforetax roceusingplbeforetax roausingplbeforetax roeusingnetincome roceusingnetincome roausingnetincome enterprisevalue

 
*save "$pathdata_raw/LC/step2/Finan_`coun_loop'.dta", replace
 save "$pathdata_raw/step2/Finan_`coun_loop'_USD.dta", replace
}	

