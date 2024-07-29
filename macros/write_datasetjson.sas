%macro write_datasetjson(
  dataset=,
  jsonpath=,
  usemetadata=N,
  metadatalib=,
  datasetJSONVersion=1.1.0,
  fileOID=,
  originator=,
  sourceSystem=,
  sourceSystemVersion=,
  studyOID=,
  metaDataVersionOID=,
  metaDataRef=,
  pretty=NOPRETTY
  ) / des = 'Write a SAS dataset to a Dataset-JSON file';

  %local
    _Random
    _SaveOptions1
    _SaveOptions2
    _Missing
    _create_temp_dataset_sas
    dataset_new dataset_name dataset_label _records
    _studyOID _metaDataVersionOID
    _itemGroupOID _isReferenceData
    creationDateTime modifiedDateTime
    _decimal_variables
    _dataset_to_write;


  %let _Random=%sysfunc(putn(%sysevalf(%sysfunc(ranuni(0))*10000,floor),z4.));

  %* Save options;
  %let _SaveOptions1 = %sysfunc(getoption(dlcreatedir));
  %let _SaveOptions2 = %sysfunc(getoption(compress, keyword)) %sysfunc(getoption(reuse, keyword));
  options dlcreatedir;
  options compress=Yes reuse=Yes;

  %if %sysevalf(%superq(datasetJSONVersion)=, boolean) %then %let datasetJSONVersion = %str(1.1.0);

  %let dataset_label=;
  %let _itemGroupOID=;
  %let _studyOID=;
  %let _metaDataVersionOID=;
  %let creationDateTime=%sysfunc(datetime(), is8601dt.);
  %let modifiedDateTime=;
  %let _create_temp_dataset_sas=0;

  %******************************************************************************;
  %* Parameter checks                                                           *;
  %******************************************************************************;

  %* Check for missing parameters ;
  %let _Missing=;
  %if %sysevalf(%superq(dataset)=, boolean) %then %let _Missing = &_Missing dataset;
  %if %sysevalf(%superq(jsonpath)=, boolean) %then %let _Missing = &_Missing jsonpath;
  %if %sysevalf(%superq(usemetadata)=, boolean) %then %let _Missing = &_Missing usemetadata;

  %if %length(&_Missing) gt 0
    %then %do;
      %put ERR%str(OR): [&sysmacroname] Required macro parameter(s) missing: &_Missing;
      %goto exit_macro;
    %end;

  %* Rule: usemetadata has to be Y or N  *;
  %if "%substr(%upcase(&usemetadata),1,1)" ne "Y" and "%substr(%upcase(&usemetadata),1,1)" ne "N" %then
  %do;
    %put ERR%str(OR): [&sysmacroname] Required macro parameter usemetadata=&usemetadata must be Y or N.;
    %goto exit_macro;
  %end;

  %* Rule: when usemetadata eq Y then metadatalib can not be empty *;
  %if "%substr(%upcase(&usemetadata),1,1)" eq "Y" and %sysevalf(%superq(metadatalib)=, boolean) %then
  %do;
    %put ERR%str(OR): [&sysmacroname] When usemetadata=Y, then parameter metadatalib can not be empty.;
    %goto exit_macro;
  %end;

  %* Rule: allowed versions *;
  %if %substr(&datasetJSONVersion,1,3) ne %str(1.1) %then
  %do;
    %put ERR%str(OR): [&sysmacroname] Macro parameter datasetJSONVersion=&datasetJSONVersion. Allowed values: 1.1.x.;
    %goto exit_macro;
  %end;

  %******************************************************************************;
  %* End of parameter checks                                                    *;
  %******************************************************************************;

  /* Get modifiedDateTime */
  proc sql noprint;
    select put(modate, e8601dt.) into :modifiedDateTime 
    from sashelp.vtable 
    where memname = upcase("%scan(&dataset, 2, %str(.))") and 
          libname = upcase("%scan(&dataset, 1, %str(.))") and memtype = "DATA";
  quit;
  
  /* Create temp SAS dataset */
  %let dataset_name=%scan(&dataset, -1, %str(.));
  %let dataset_new=&dataset;
  libname sas&_Random "%sysfunc(pathname(work))/sas&_Random";
  proc copy in=%scan(&dataset, 1, %str(.)) out=sas&_Random memtype=data datecopy;
    select &dataset_name;
  run;
  %let dataset_new=sas&_Random..&dataset_name;
  
  %let _create_temp_dataset_sas=1;

  /* Derive _isReferenceData */
  %if %cstutilcheckvarsexist(_cstDataSetName=&dataset_new, _cstVarList=usubjid)=0 %then
    %do;
      %let _isReferenceData=Yes;
    %end;  

  /* Get number of records */
  %let _records=%cstutilnobs(_cstDataSetName=&dataset_new);

  %if %substr(%upcase(&UseMetadata),1,1) eq Y %then %do;
    /* Get StudyOID and metaDataVersionOID from the metadata */
    proc sql noprint;
      %if %sysfunc(exist(&metadatalib..metadata_study)) %then %do;
        select studyOID, metaDataVersionOID into :_studyOID trimmed, :_metaDataVersionOID trimmed
          from &metadatalib..metadata_study;
      %end;
    /* Get dataset label and _itemGroupOID from the metadata */
      %if %sysfunc(exist(&metadatalib..metadata_tables)) %then %do;
        select label, oid into :dataset_label trimmed, :_temGroupOID trimmed
          from &metadatalib..metadata_tables
            where upcase(name)="%upcase(&dataset_name)";
      %end;
    quit;
  %end;

  /* Get StudyOID, metaDataVersionOID, itemGroupOID, and dataset label */
  %if %sysevalf(%superq(_studyOID)=, boolean) and %sysevalf(%superq(studyOId)=, boolean)=0 %then
    %let _studyOID=&studyOId;

  %if %sysevalf(%superq(_metaDataVersionOID)=, boolean) and %sysevalf(%superq(metaDataVersionOID)=, boolean)=0 %then
    %let _metaDataVersionOID=&metaDataVersionOID;

  %if %sysevalf(%superq(_itemGroupOID)=, boolean) %then %let _itemGroupOID=IG.%upcase(&dataset_name);

  %if %sysevalf(%superq(dataset_label)=, boolean) %then
    %let dataset_label=%cstutilgetattribute(_cstDataSetName=&dataset_new,_cstAttribute=LABEL);

  %if %sysevalf(%superq(dataset_label)=, boolean) %then %do;
/*
    %let dataset_label=%sysfunc(lowcase(&dataset_name));
    %put %str(WAR)NING: [&sysmacroname] Dataset &dataset has no dataset label. "&dataset_label" will be used as label.;
*/
    %put %str(WAR)NING: [&sysmacroname] Dataset &dataset has no dataset label.;
  %end;

  %put NOTE: DATASET=&dataset_name &=_records &=_isReferenceData &=_itemGroupOID dslabel=%bquote(&dataset_label);


 
  %if %substr(%upcase(&UseMetadata),1,1) eq Y %then %do;
    /* Get column metadata - oid, label, type, length, displayformat, keysequence  */
    data work._column_metadata(keep=OID name label order datatype targetdatatype length displayFormat keySequence);
      retain OID name label datatype length displayFormat keySequence;
      length _label $ 32;
      set &metadatalib..metadata_columns(
          where=(upcase(dataset_name) = %upcase("&dataset_name"))
          drop=length
          rename=(json_length=length)
        );
        _label = "";
        if missing(oid) then putlog "WAR" "NING: [&sysmacroname] Missing oid for variable: " name ;
        if missing(name) then putlog "WAR" "NING: [&sysmacroname] Missing name for variable: " oid ;
        if missing(label) then do;
          _label = lowcase(name);
          putlog "WAR" "NING: [&sysmacroname] Missing label for variable: " name +(-1) ", " oid= +(-1) ". " _label "will be used as label.";
          label = _label;
        end;
        if missing(datatype) then putlog "WAR" "NING: [&sysmacroname] Missing dataType for variable: " name +(-1) ", " oid=;
    run;


    /* Check lengths */
    proc contents noprint varnum data=&dataset_new
      out=work.column_metadata_sas(keep=name type length varnum);
    run;

    proc sql noprint;
      create table work.column_metadata as
      select
        t2.name as sas_name,
        t2.length as sas_length,
        t2.type as sas_type,
        t2.varnum,
        t1.*
        from work.column_metadata_sas t2
          left join work._column_metadata t1
        on t1.name = t2.name
        order by varnum
        ;
    quit ;

    data work.column_metadata(drop=sas_type sas_length sas_name order varnum);
      set work.column_metadata;
      if (sas_type=2) and (not missing(length)) and (length lt sas_length)
        then putlog 'WAR' 'NING:' "%upcase(&dataset_name)." name +(-1) ": metadata length is smaller than SAS length - "
                    length= +(-1) ", SAS length=" sas_length;
      if missing(name) then do;
        putlog 'WAR' 'NING:' "%upcase(&dataset_name)." sas_name
                +(-1) ": variable is missing from metadata. SAS metadata will be used.";
        OID = cats("IT", ".", upcase("&dataset_name"), ".", upcase(sas_name));
        name = sas_name;
        length = sas_length;
        if sas_type=1 then dataType="float";
                      else dataType="string";
        label = propcase(name);
      end;
    run;

    proc delete data=work._column_metadata;
    run;
    proc delete data=work.column_metadata_sas;
    run;

  %end;
  %else %do;
    
    %create_template(type=COLUMNS, out=work.column_metadata_template);
    /* Get column metadata from the datasets - label, type, length, format and derive as much as we can */
    proc contents noprint varnum data=&dataset_new
      out=work.column_metadata(
        keep=varnum name type format formatl formatd length label
        rename=(format=displayFormat type=sas_type)
      );
    run;

    proc sort data=work.column_metadata;
      by varnum;
    run;

    data work.column_metadata(drop=sas_type varnum formatl formatd _label);
      retain OID name label dataType targetDataType length;
      length OID $ 128 dataType targetDataType _label $ 32;
      set work.column_metadata_template work.column_metadata;
      _label = "";
      targetDataType = "";
      OID = cats("IT", ".", upcase("&dataset_name"), ".", upcase(name));
      if sas_type=1 then do;
        dataType="float";
        length = .;
      end;  
      else do;
        dataType="string";
      end;  
      /* datetime, date, and time variables will be transfered as ISO 8601 strings */              
      if sas_type = 1 and (scan(upcase(displayFormat), 1, ".") = "E8601DA" or scan(upcase(displayFormat), 1, ".") = "DATE") then do;
        dataType = "date";
        targetDataType = "integer";
      end;
      if sas_type = 1 and (scan(upcase(displayFormat), 1, ".") = "E8601TM" or scan(upcase(displayFormat), 1, ".") = "TIME") then do;
        dataType = "time";
        targetDataType = "integer";
      end;
      if sas_type = 1 and (scan(upcase(displayFormat), 1, ".") = "E8601DT" or scan(upcase(displayFormat), 1, ".") = "DATETIME") then do;
        dataType = "datetime";
        targetDataType = "integer";
      end;
                    
      if formatl gt 0 then displayFormat=cats(displayFormat, put(formatl, best.), ".");
      if formatd gt 0 then displayFormat=cats(displayFormat, put(formatd, best.));
      %* put a dot on the end of format if we are still missing it;
      if (not missing(displayFormat)) and index(displayFormat,'.')=0 then displayFormat=strip(displayFormat)||'.';
      if missing(label) then do;
        _label = propcase(name);
        putlog "WAR" "NING: [&sysmacroname] Missing label for variable " name +(-1) ", " oid= +(-1) ". " _label "will be used as label.";
        label = _label;
      end;
      if missing(dataType) then putlog "WAR" "NING: [&sysmacroname] Missing type for variable " name +(-1) ", "  oid=;
    run;

  %end;

  %if %cstutilcheckvarsexist(_cstDataSetName=&dataset_new, _cstVarList=ITEMGROUPDATASEQ) %then %do;
  /* There already is a ITEMGROUPDATASEQ variable */
    %put %str(WAR)NING: [&sysmacroname] Dataset &dataset_new already contains a variable ITEMGROUPDATASEQ.;
    %if %cstutilgetattribute(_cstDataSetName=&dataset_new, _cstVarName=ITEMGROUPDATASEQ, _cstAttribute=VARTYPE) eq C %then %do;
      /* The datatype of the ITEMGROUPDATASEQ variable is character*/
      %put %str(ERR)OR: [&sysmacroname] The ITEMGROUPDATASEQ in the dataset &dataset_new is a character variable.;
      %put %str(ERR)OR: [&sysmacroname] It is required to drop this variable.;
    %end;
    %let _dataset_to_write = &dataset_new;
  %end;
  %else %do;
    /* Create the numeric ITEMGROUPDATASEQ variable */
    /* Create a 1-obs dataset with the same structure as the column_metadata dataset */
    proc sql noprint;
      create table itemgroupdataseq_metadata
        like work.column_metadata;
      insert into itemgroupdataseq_metadata
        set OID="ITEMGROUPDATASEQ", name="ITEMGROUPDATASEQ", label="Record Identifier",
          dataType="integer";
    quit;

    data work.column_metadata;
      set itemgroupdataseq_metadata
          work.column_metadata(where=(upcase(name) ne "ITEMGROUPDATASEQ"));
    run;

    data work.column_data;
      length ITEMGROUPDATASEQ 8.;
      set &dataset_new;
      ITEMGROUPDATASEQ = _n_;
    run;
    %let _dataset_to_write = work.column_data;

    proc delete data=work.itemgroupdataseq_metadata;
    run;

  %end;

  %******************************************************************************;
  %let _decimal_variables=;
  proc sql noprint;
    select name into :_decimal_variables separated by ' '
      from work.column_metadata
      where dataType='decimal' and targetDataType='decimal';  
  quit;
 
  %if %sysevalf(%superq(_decimal_variables)=, boolean)=0 %then %do;
    %put NOTE: [&sysmacroname] Dataset=%upcase(&dataset_name): numeric variables converted to string: &_decimal_variables;
    %convert_num_to_char(ds=&_dataset_to_write, outds=&_dataset_to_write, varlist=&_decimal_variables);
  %end;  


  %******************************************************************************;

  %create_template(type=STUDY, out=work.study_metadata);
  
  proc sql;
  insert into work.study_metadata  
    set fileoid = "&fileOID",
        creationdatetime = "&creationdatetime",
        modifiedDateTime = "&modifiedDateTime",
        datasetJSONVersion = "&datasetJSONVersion",
        originator = "&originator",
        sourcesystem = "&sourceSystem",
        sourcesystemversion = "&sourceSystemVersion",
        studyoid = "&_studyOID",
        metadataversionoid = "&_metaDataVersionOID",
        metaDataRef = "&metaDataRef"
    ;
  quit;
  
  %create_template(type=TABLES, out=work.table_metadata);

  proc sql;
  insert into work.table_metadata  
    set oid = "&_itemGroupOID"
        , isReferenceData = "&_isReferenceData"
        , records = &_records
        , name = "%upcase(&dataset_name)"
        %if %sysevalf(%superq(dataset_label)=, boolean)=0 %then , label = "%nrbquote(&dataset_label)";
    ;
  quit;  

  filename json&_random "&jsonpath";

  data work.column_metadata;
    retain itemOID name label dataType targetDataType length displayFormat keySequence;
    set work.column_metadata(rename=(oid=itemOID));
  run;  
  
  %write_datasetjson_1_1(
    outRef=json&_random,
    technicalMetadata=work.study_metadata,
    tableMetadata=work.table_metadata,
    columnMetadata=work.column_metadata,
    rowdata=&_dataset_to_write,
    prettyNoPretty=&pretty
  );
  
  filename json&_random clear;

  %if &_create_temp_dataset_sas=1 %then %do;
    proc delete data=sas&_Random..&dataset_name;
    run;

    %put %sysfunc(filename(fref,%sysfunc(pathname(sas&_Random))));
    %put %sysfunc(fdelete(&fref));
    libname sas&_Random clear;

  %end;

  %if %sysfunc(exist(work.column_metadata)) %then %do;
    proc delete data=work.column_metadata;
    run;
  %end;
  %if %sysfunc(exist(work.column_data)) %then %do;
    proc delete data=work.column_data;
    run;
  %end;

  %exit_macro:

  %* Restore options;
  options &_SaveOptions1;
  options &_SaveOptions2;

%mend write_datasetjson;
