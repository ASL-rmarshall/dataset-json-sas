%macro read_datasetjson(
  jsonpath=,
  datalib=,
  dropseqvar=N,
  savemetadata=N,
  metadatalib=
  ) / des = 'Read a Dataset-JSON file to a SAS dataset';

  %local _Missing
         _SaveOptions1
         _SaveOptions2
         _Random
         _clinicalreferencedata_ _items_ _itemdata_ _itemgroupdata_ ItemGroupOID _ItemGroupName
         dslabel dsname variables rename label length format
         _decimal_variables;

  %let _Random=%sysfunc(putn(%sysevalf(%sysfunc(ranuni(0))*10000,floor),z4.));

  %* Save options;
  %let _SaveOptions1 = %sysfunc(getoption(dlcreatedir));
  options dlcreatedir;

  %******************************************************************************;
  %* Parameter checks                                                           *;
  %******************************************************************************;

  %* Check for missing parameters ;
  %let _Missing=;
  %if %sysevalf(%superq(jsonpath)=, boolean) %then %let _Missing = &_Missing jsonpath;
  %if %sysevalf(%superq(datalib)=, boolean) %then %let _Missing = &_Missing datalib;
  %if %sysevalf(%superq(dropseqvar)=, boolean) %then %let _Missing = &_Missing dropseqvar;
  %if %sysevalf(%superq(savemetadata)=, boolean) %then %let _Missing = &_Missing savemetadata;

  %if %length(&_Missing) gt 0
    %then %do;
      %put ERR%str(OR): [&sysmacroname] Required macro parameter(s) missing: &_Missing;
      %goto exit_macro;
    %end;

  %* Rule: dropseqvar has to be Y or N  *;
  %if "%substr(%upcase(&dropseqvar),1,1)" ne "Y" and "%substr(%upcase(&dropseqvar),1,1)" ne "N" %then
  %do;
    %put ERR%str(OR): [&sysmacroname] Required macro parameter dropseqvar=&dropseqvar must be Y or N.;
    %goto exit_macro;
  %end;

  %* Rule: savemetadata has to be Y or N  *;
  %if "%substr(%upcase(&savemetadata),1,1)" ne "Y" and "%substr(%upcase(&savemetadata),1,1)" ne "N" %then
  %do;
    %put ERR%str(OR): [&sysmacroname] Required macro parameter savemetadata=&savemetadata must be Y or N.;
    %goto exit_macro;
  %end;

%******************************************************************************;
  %* End of parameter checks                                                    *;
  %******************************************************************************;


  %* Save options;
  %let _SaveOptions2 = %sysfunc(getoption(compress, keyword)) %sysfunc(getoption(reuse, keyword));
  options compress=Yes reuse=Yes;

  filename json&_Random "&jsonpath";
  filename map&_Random "../maps/map&_Random._%scan(&jsonpath, -2, %str(.\/)).map";
  libname out_&_Random "%sysfunc(pathname(work))/%scan(&jsonpath, -2, %str(.\/))";

  libname json&_Random json map=map&_Random automap=create fileref=json&_Random
          %if "%substr(%upcase(&savemetadata),1,1)" ne "Y" %then noalldata; ordinalcount=none;
  proc copy in=json&_Random out=out_&_Random;
  run;

  proc sql noprint;
    select datasetJSONVersion into :datasetJSONVersion separated by ' '
      from out_&_Random..root;
  quit;
  
  %put &=datasetJSONVersion;
  
  %* Restore options;
  options &_SaveOptions2;

  /* Find the names of the dataset that were created */

  %let _clinicalreferencedata_=;
  %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.0" %then %do;
    %if %sysfunc(exist(out_&_Random..clinicaldata))
      %then %let _clinicalreferencedata_=out_&_Random..clinicaldata;
      %else %if %sysfunc(exist(out_&_Random..referencedata))
        %then %let _clinicalreferencedata_=out_&_Random..referencedata;
        %else %do;
          %put ERR%str(OR): [&sysmacroname] JSON file &jsonpath contains no "clinicalData" or "referenceData" key.;
          %goto exit_macro;
        %end;  
  %end;

  proc sql noprint;
    create table members
    as select upcase(memname) as name
    from dictionary.tables
    where upcase(libname)=upcase("OUT_&_Random") and memtype="DATA"
    ;
  quit;

  %let _items=;
  %let _itemdata=;
  %let _itemgroupdata_=;
  data _null_;
    set members;
    if index(upcase(name), '_ITEMS') then
      call symputx('_items_', strip(name));
    if index(upcase(name), '_ITEMDATA') then
      call symputx('_itemdata_', strip(name));
    if index(upcase(name), 'ITEMGROUPDATA_') then
      call symputx('_itemgroupdata_', strip(name));
  run;

  %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.1" %then %do;
    %let _itemgroupdata_=root;  
    %let _items_=columns;
    %let _itemdata_=rows;
  %end;  

  %if %sysevalf(%superq(_itemgroupdata_)=, boolean)
    %then %do;
      %put ERR%str(OR): [&sysmacroname] JSON file &jsonpath contains no "itemGroupData" key.;
      %goto exit_macro;      
    %end;  

  %if %sysevalf(%superq(_items_)=, boolean)
    %then %do;
      %put ERR%str(OR): [&sysmacroname] JSON file &jsonpath contains no "items" key.;
      %goto exit_macro;      
    %end;  

  %if %sysevalf(%superq(_itemdata_)=, boolean)
    %then %do;
      %put ERR%str(OR): [&sysmacroname] JSON file &jsonpath contains no "itemData" key.;
      %goto exit_macro;      
    %end;  

  proc delete data=work.members;
  run;

  proc sql noprint;
    select name into :variables separated by ' '
      from out_&_Random..&_items_;
    select cats("element", monotonic(), '=', name) into :rename separated by ' '
      from out_&_Random..&_items_;
    select cats(name, '=', quote(strip(label))) into :label separated by ' '
      from out_&_Random..&_items_
      where not(missing(label));
    select catt(name, ' $', length) into :length separated by ' '
      from out_&_Random..&_items_
    %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.0" %then %do;
      where type="string" and (not(missing(length)));
    %end;
    %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.1" %then %do;
      where datatype="string" and (not(missing(length)));
    %end;
  quit;

  %put &=variables;
  %put &=rename;
  %put &=label;
  %put &=length;

  %let dslabel=;
  %let dsname=;
  proc sql noprint;
    select label, name into :dslabel, :dsname trimmed
      from out_&_Random..&_itemgroupdata_
    ;
  quit;

  proc copy in=out_&_Random out=&datalib;
    select &_itemdata_;
  run;

%if "%substr(%upcase(&savemetadata),1,1)" eq "Y" %then %do;

  %let ItemGroupOID=;
    %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.0" %then %do;
      proc sql noprint;
        select P3 into :ItemGroupOID trimmed
          from out_&_Random..alldata
          where P2 = "itemGroupData" and P = 3;
      quit;
    %end;
    %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.1" %then %do;
      proc sql noprint;
        select ItemGroupOID into :ItemGroupOID trimmed
          from out_&_Random..root;
      quit;
    %end;
    
  %if not %sysfunc(exist(&metadatalib..metadata_study)) %then %create_template(type=STUDY, out=&metadatalib..metadata_study);;
  %if not %sysfunc(exist(&metadatalib..metadata_tables)) %then %create_template(type=TABLES, out=&metadatalib..metadata_tables);;
  %if not %sysfunc(exist(&metadatalib..metadata_columns)) %then %create_template(type=COLUMNS, out=&metadatalib..metadata_columns);;

  %if %sysfunc(exist(out_&_Random..root)) %then %do;
    data work._metadata_study;
      merge out_&_Random..root &_clinicalreferencedata_;
    run;
  %end;
  %else %do;
    %if %sysfunc(exist(&_clinicalreferencedata_)) %then %do;
      data work._metadata_study;
        set &_clinicalreferencedata_;
      run;
    %end;
  %end;

  data &metadatalib..metadata_study;
    set &metadatalib..metadata_study work._metadata_study;
  run;

  proc delete data=work._metadata_study;
  run;

  %if %cstutilcheckvarsexist(_cstDataSetName=out_&_Random..&_itemgroupdata_, _cstVarList=isReferenceData) 
  %then %do;
    %if %cstutilgetattribute(_cstDataSetName=out_&_Random..&_itemgroupdata_, _cstVarName=isReferenceData, _cstAttribute=VARTYPE) eq N 
    %then %do;
      data out_&_Random..&_itemgroupdata_;
        length isReferenceData $3;
        set out_&_Random..&_itemgroupdata_(rename=(isReferenceData = _isReferenceData));
          if _isReferenceData = 1 then isReferenceData = "Yes";
          if _isReferenceData = 0 then isReferenceData = "No";
          drop _isReferenceData;
      run;  
    %end;
  %end;

  data &metadatalib..metadata_tables;
    set &metadatalib..metadata_tables out_&_Random..&_itemgroupdata_(in=inigd /* drop=records */);
    if inigd then do;
      oid = "&ItemGroupOID";
      call symputx('_ItemGroupName', name);
    end;
  run;

  data work.&_items_;
    set out_&_Random..&_items_;
    order = _n_;
  run;

  %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.0" %then %do;
    data &metadatalib..metadata_columns(%if %substr(%upcase(&DropSeqVar),1,1) eq Y %then where=(upcase(name) ne "ITEMGROUPDATASEQ"););
      set &metadatalib..metadata_columns work.&_items_(rename=(type=json_datatype) in=init);
      if init then dataset_name = "&_ItemGroupName";
    run;
  %end;
  %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.1" %then %do;
    data &metadatalib..metadata_columns(%if %substr(%upcase(&DropSeqVar),1,1) eq Y %then where=(upcase(name) ne "ITEMGROUPDATASEQ"););
      set &metadatalib..metadata_columns work.&_items_(rename=(datatype=json_datatype ItemOID=OID) in=init);
      if init then dataset_name = "&_ItemGroupName";
    run;
  %end;

  proc delete data=work.&_items_;
  run;

%end;

  /* get formats from Dataset-JSON metadata, but only when the displayformat variable exists */
  %let format=;
  %if %cstutilcheckvarsexist(_cstDataSetName=out_&_Random..&_items_, _cstVarList=displayformat) %then %do;
    proc sql noprint;
      select catx(' ', name, strip(displayformat)) into :format separated by ' '
          from out_&_Random..&_items_
          where (not(missing(displayformat)) and (displayformat ne ".")) /* and (type in ('integer' 'float' 'double' 'decimal')) */;
    quit;
  %end;
  
  %put &=format;

  proc datasets library=&datalib noprint nolist nodetails;
    %if %sysfunc(exist(&datalib..&dsname)) %then %do; delete &dsname; %end;
    change &_itemdata_ = &dsname;
    modify &dsname %if %sysevalf(%superq(dslabel)=, boolean)=0 %then %str((label = %sysfunc(quote(%nrbquote(&dslabel)))));;
      rename &rename;
      label &label;
  quit;
  

  %******************************************************************************;
  %let _decimal_variables=;
  proc sql noprint;
    select name into :_decimal_variables separated by ' '
      from &metadatalib..metadata_columns
      where json_datatype='decimal' and targetdatatype='decimal' and upcase(dataset_name) = upcase("&dsname");  
  quit;
 
  %if %sysevalf(%superq(_decimal_variables)=, boolean)=0 %then %do;

    %put #### &=dsname &=_decimal_variables;
    %convert_char_to_num(ds=&datalib..&dsname, outds=&datalib..&dsname, varlist=&_decimal_variables);

    proc datasets library=&datalib noprint nolist nodetails;
      modify &dsname %if %sysevalf(%superq(dslabel)=, boolean)=0 %then %str((label = %sysfunc(quote(%nrbquote(&dslabel)))));;
    quit;

  %end;  

%******************************************************************************;
  
  

  /* Update lengths */
  proc sql noprint;
    select catt(d.name, ' $', i.length) into :length separated by ' '
      from dictionary.columns d,
           out_&_Random..&_items_ i
    where upcase(libname)="%upcase(&datalib)" and
         upcase(memname)="%upcase(&dsname)" and
         d.name = i.name and
         d.type="char" and (not(missing(i.length))) and (i.length gt d.length)
   ;
  quit ;

  data &datalib..&dsname(
      %if %sysevalf(%superq(dslabel)=, boolean)=0 %then %str(label = %sysfunc(quote(%nrbquote(&dslabel))));
      %if %substr(%upcase(&DropSeqVar),1,1) eq Y %then drop=ITEMGROUPDATASEQ;
    );
    retain &variables;
    length &length;
    /* %if %sysevalf(%superq(format)=, boolean)=0 %then format &format;; */
    set &datalib..&dsname;
  run;



  /*  Validate datatypes and lengths */
  proc sql ;
   create table column_metadata
   as select
    case upcase(d.name)
      when "ITEMGROUPDATASEQ" then d.name
      else cats("IT.", "%upcase(&dsname).", d.name)
    end as OID,
    d.name,
    %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.0" %then %do;
      d.type as DataType,
      i.type,
    %end;
    %if "%substr(%upcase(&datasetJSONVersion),1,3)" = "1.1" %then %do;
      d.type as datatype,
      i.datatype as type,
    %end;
    d.length as sas_length,
    i.length,
    d.format
   from dictionary.columns d,
        out_&_Random..&_items_ i
   where upcase(libname)="%upcase(&datalib)" and
         upcase(memname)="%upcase(&dsname)" and
         d.name = i.name
   ;
  quit ;

  data _null_;
    set column_metadata;
    if DataType="char" and not (type in ('string' 'datetime' 'date' 'time')) then put "WAR" "NING: [&sysmacroname] TYPE ISSUE: dataset=&dsname " OID= name= DataType= type=;
    if DataType="num" and not (type in ('integer' 'double' 'float' 'decimal')) then put "WAR" "NING: [&sysmacroname] TYPE ISSUE: dataset=&dsname " OID= name= DataType= type=;
    if DataType="char" and not(missing(length)) and (length lt sas_length) then put "WAR" "NING: [&sysmacroname] LENGTH ISSUE: dataset=&dsname " OID= name= length= sas_length=;
  run;

  proc delete data=work.column_metadata;
  run;

  libname json&_Random clear;
  filename json&_Random clear;
  filename map&_Random clear;

  proc datasets nolist lib=out_&_Random kill;
  quit;

  %put %sysfunc(filename(fref,%sysfunc(pathname(out_&_Random))));
  %put %sysfunc(fdelete(&fref));
  libname out_&_Random clear;


  %exit_macro:

  %* Restore options;
  options &_SaveOptions1;

%mend read_datasetjson;
