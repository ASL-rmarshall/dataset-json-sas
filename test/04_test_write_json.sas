%* update this location to your own location;
%let root=/_github/lexjansen/dataset-json-sas;
%include "&root/test/config.sas";

data _null_;
  length fref $8 name $64 jsonfile $200 code $400;
  did = filename(fref,"%sysfunc(pathname(dataadam))");
  did = dopen(fref);
  do i = 1 to dnum(did);
    if index(dread(did,i), "sas7bdat") then do;
      name=scan(dread(did,i), 1, ".");
      jsonfile=cats("&root/json_out/adam/", name, ".json");
      code=cats('%nrstr(%write_json(',
                          'dataset=dataadam.', name, ', ', 
                          'jsonfile=', jsonfile, ', ',
                          'usemetadata=1, ',
                          'metadatalib=metaadam',
                        ');)');
      call execute(code);
    end;
  end;
  did = dclose(did);
  did = filename(fref);
run;

%let StudyOID=%str(cdisc.com/CDISCPILOT01);
%let MetaDataVersionOID=%str(MDV.MSGv2.0.SDTMIG.3.3.SDTM.1.7);

data _null_;
  length fref $8 name $64 jsonfile $200 code $400;
  did = filename(fref,"%sysfunc(pathname(datasdtm))");
  did = dopen(fref);
  do i = 1 to dnum(did);
    if index(dread(did,i), "sas7bdat") then do;
      name=scan(dread(did,i), 1, ".");
      jsonfile=cats("&root/json_out/sdtm/", name, ".json");
      code=cats('%nrstr(%write_json(',
                          'dataset=datasdtm.', name, ', ', 
                          'jsonfile=', jsonfile, ', ',
                          'usemetadata=0, ',
                          'metadatalib=metasdtm, ',
                          "_studyOID=&StudyOID, ",
                          "_MetaDataVersionOID=&MetaDataVersionOID",
                        ');)');
          call execute(code);
    end;
  end;
  did = dclose(did);
  did = filename(fref);
run;

/*
libname metaadam clear;
libname metasdtm clear;
libname dataadam clear;
libname datasdtm clear;
*/