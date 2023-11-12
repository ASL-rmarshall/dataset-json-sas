options sasautos = (%qsysfunc(compress(%qsysfunc(getoption(SASAUTOS)),%str(%()%str(%)))) "&project_folder/macros");
options ls=max;
filename luapath ("&project_folder/lua");

%let now_iso8601=%sysfunc(datetime(), is8601dt.);
%let today_iso8601=%sysfunc(date(), b8601da8.);  

libname dataadam "&project_folder/data/adam";
libname datasdtm "&project_folder/data/sdtm";

libname outadam  "&project_folder/data_out/adam";
libname outsdtm  "&project_folder/data_out/sdtm";

libname metaadam "&project_folder/metadata/adam";
libname metasdtm "&project_folder/metadata/sdtm";

libname metasvad "&project_folder/metadata_save/adam";
libname metasvsd "&project_folder/metadata_save/sdtm";

libname results "&project_folder/results";
libname macros "&project_folder/macros";


%* This is needed to be able to run Python;
%* Update to your own locations           ;
options set=MAS_PYPATH="&project_folder/venv/Scripts/python.exe";
options set=MAS_M2PATH="%sysget(SASROOT)/tkmas/sasmisc/mas2py.py";

%let fcmplib=sasuser;
/* Compile the validate_datasetjson function if not already there */
%if not %sysfunc(exist(&fcmplib..datasetjson_funcs)) %then %do;
  %include "&project_folder/macros/validate_datasetjson.sas";
%end;

options cmplib=&fcmplib..datasetjson_funcs;
