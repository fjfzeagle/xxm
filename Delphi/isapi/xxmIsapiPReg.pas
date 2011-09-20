unit xxmIsapiPReg;

interface

uses Windows, SysUtils, xxm, xxmPReg, MSXML2_TLB;

type
  TXxmProjectCacheEntry=class(TXxmProjectEntry)
  protected
    procedure SetSignature(const Value: AnsiString); override;
    function GetExtensionMimeType(x:AnsiString): AnsiString; override;
    procedure LoadProject; override;
  published
    constructor Create(Name,FilePath:WideString;LoadCopy:boolean);
  public
    destructor Destroy; override;
  end;

  TXxmProjectCache=class(TObject)
  private
    ProjectCacheSize:integer;
    ProjectCache:array of TXxmProjectCacheEntry;
    FRegFilePath,FDefaultProject,FSingleProject:AnsiString;
    FRegFileLoaded:boolean;
    procedure ClearAll;
    function Grow:integer;
    function FindOpenProject(LowerCaseName:AnsiString):integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Refresh;

    function GetProject(Name:WideString):TXxmProjectCacheEntry;
    procedure ReleaseProject(Name:WideString);
    property DefaultProject:AnsiString read FDefaultProject;
    property SingleProject:AnsiString read FSingleProject;
  end;

  TXxmAutoBuildHandler=function(pce:TXxmProjectCacheEntry;
    Context: IXxmContext; ProjectName:WideString):boolean;

  EXxmProjectRegistryError=class(Exception);
  EXxmProjectNotFound=class(Exception);
  EXxmModuleNotFound=class(Exception);
  EXxmProjectLoadFailed=class(Exception);
  EXxmFileTypeAccessDenied=class(Exception);
  EXxmProjectAliasDepth=class(Exception);

var
  XxmProjectCache:TXxmProjectCache;

implementation

uses Registry, Variants, xxmCommonUtils;

resourcestring
  SXxmProjectRegistryError='Could not open project registry "__"';
  SXxmProjectNotFound='xxm Project "__" not defined.';
  SXxmModuleNotFound='xxm Module "__" does not exist.';
  SXxmProjectLoadFailed='xxm Project load "__" failed.';
  SXxmFileTypeAccessDenied='Access denied to this type of file';
  SXxmProjectAliasDepth='xxm Project "__": aliasses are limited to 8 in sequence';

{ TXxmProjectCacheEntry }

constructor TXxmProjectCacheEntry.Create(Name, FilePath: WideString; LoadCopy: boolean);
begin
  inherited Create(LowerCase(Name));//lowercase here!
  FFilePath:=FilePath;
  if LoadCopy then FLoadPath:=FFilePath+'_'+IntToHex(GetCurrentProcessId,4);
end;

destructor TXxmProjectCacheEntry.Destroy;
begin
  //pointer(FProject):=nil;//strange, project modules get closed before this happens
  inherited;
end;

function TXxmProjectCacheEntry.GetExtensionMimeType(x:AnsiString): AnsiString;
begin
  if (x='.xxl') or (x='.xxu') or (x='.exe') or (x='.dll') or (x='.xxmp') or (x='.udl') then //more? settings?
    raise EXxmFileTypeAccessDenied.Create(SXxmFileTypeAccessDenied);
  Result:=inherited GetExtensionMimeType(x);
end;

procedure TXxmProjectCacheEntry.LoadProject;
begin
  inherited;
  if not ProjectLoaded then FFilePath:='';//force refresh next time
end;

procedure TXxmProjectCacheEntry.SetSignature(const Value: AnsiString);
var
  doc:DOMDocument;
  x:IXMLDOMElement;
begin
  FSignature := Value;
  doc:=CoDOMDocument.Create;
  try
    doc.async:=false;
    if not(doc.load(XxmProjectCache.FRegFilePath)) then
      raise EXxmProjectRegistryError.Create(StringReplace(
        SXxmProjectRegistryError,'__',XxmProjectCache.FRegFilePath,[])+#13#10+
        doc.parseError.reason);
    x:=doc.documentElement.selectSingleNode(
      'Project[@Name="'+Name+'"]') as IXMLDOMElement;
    if x=nil then
      raise EXxmProjectNotFound.Create(StringReplace(
        SXxmProjectNotFound,'__',Name,[]));
    x.setAttribute('Signature',FSignature);
    doc.save(XxmProjectCache.FRegFilePath);
    //force XxmProjectCache.Refresh?
  finally
    x:=nil;
    doc:=nil;
  end;
end;

{ TXxmProjectCache }

constructor TXxmProjectCache.Create;
var
  i:integer;
begin
  inherited;
  ProjectCacheSize:=0;
  FDefaultProject:='xxm';
  FSingleProject:='';

  SetLength(FRegFilePath,$400);
  SetLength(FRegFilePath,GetModuleFileNameA(HInstance,PAnsiChar(FRegFilePath),$400));
  if Copy(FRegFilePath,1,4)='\\?\' then FRegFilePath:=Copy(FRegFilePath,5,Length(FRegFilePath)-4);
  i:=Length(FRegFilePath);
  while not(i=0) and not(FRegFilePath[i]=PathDelim) do dec(i);
  FRegFilePath:=Copy(FRegFilePath,1,i)+'xxm.xml';
  FRegFileLoaded:=false;

  //settings?
end;

destructor TXxmProjectCache.Destroy;
begin
  ClearAll;
  inherited;
end;

function TXxmProjectCache.Grow: integer;
var
  i:integer;
begin
  i:=ProjectCacheSize;
  Result:=i;
  inc(ProjectCacheSize,16);//const growstep
  SetLength(ProjectCache,ProjectCacheSize);
  while (i<ProjectCacheSize) do
   begin
    ProjectCache[i]:=nil;
    inc(i);
   end;
end;

function TXxmProjectCache.FindOpenProject(LowerCaseName: AnsiString): integer;
begin
  Result:=0;
  //assert cache stores ProjectName already LowerCase!
  while (Result<ProjectCacheSize) and (
    (ProjectCache[Result]=nil) or not(ProjectCache[Result].Name=LowerCaseName)) do inc(Result);
  if Result=ProjectCacheSize then Result:=-1;
end;

procedure TXxmProjectCache.Refresh;
var
  doc:DOMDocument;
begin
  if not(FRegFileLoaded) then
   begin
    doc:=CoDOMDocument.Create;
    try
      doc.async:=false;
      if not(doc.load(FRegFilePath)) then
        raise EXxmProjectRegistryError.Create(StringReplace(
          SXxmProjectRegistryError,'__',FRegFilePath,[])+#13#10+
          doc.parseError.reason);
      FSingleProject:=VarToStr(doc.documentElement.getAttribute('SingleProject'));
      FDefaultProject:=VarToStr(doc.documentElement.getAttribute('DefaultProject'));
      if FDefaultProject='' then FDefaultProject:='xxm';
    finally
      doc:=nil;
    end;
    FRegFileLoaded:=true;
   end;
end;

function TXxmProjectCache.GetProject(Name: WideString): TXxmProjectCacheEntry;
var
  i,d:integer;
  n:AnsiString;
  found:boolean;
  doc:DOMDocument;
  xl:IXMLDOMNodeList;
  x,y:IXMLDOMElement;
begin
  Result:=nil;//counter warning
  n:=LowerCase(Name);
  i:=FindOpenProject(n);
  if i=-1 then
   begin
    //assert CoInitialize called
    doc:=CoDOMDocument.Create;
    try
      doc.async:=false;
      if not(doc.load(FRegFilePath)) then
       begin
        FRegFileLoaded:=false;
        raise EXxmProjectRegistryError.Create(StringReplace(
          SXxmProjectRegistryError,'__',FRegFilePath,[])+#13#10+
          doc.parseError.reason);
       end;
      //assert documentElement.nodeName='ProjectRegistry'
      FSingleProject:=VarToStr(doc.documentElement.getAttribute('SingleProject'));
      //TODO: if changed then update? raise?
      FDefaultProject:=VarToStr(doc.documentElement.getAttribute('DefaultProject'));
      if FDefaultProject='' then FDefaultProject:='xxm';
      d:=0;
      found:=false;
      while not(found) do
       begin
        //TODO: selectSingleNode case-insensitive?
        xl:=doc.documentElement.selectNodes('Project');
        x:=xl.nextNode as IXMLDOMElement;
        while not(found) and not(x=nil) do
          if LowerCase(VarToStr(x.getAttribute('Name')))=n then
            found:=true
          else
            x:=xl.nextNode as IXMLDOMElement;
        if found then
         begin
          n:=LowerCase(VarToStr(x.getAttribute('Alias')));
          if not(n='') then
           begin
            inc(d);
            if d=8 then raise EXxmProjectAliasDepth.Create(StringReplace(
              SXxmProjectAliasDepth,'__',Name,[]));
            found:=false;
           end;
         end
        else
         begin
          raise EXxmProjectNotFound.Create(StringReplace(
            SXxmProjectNotFound,'__',Name,[]));
         end;
       end;
      y:=x.selectSingleNode('ModulePath') as IXMLDOMElement;
      if y=nil then n:='' else n:=y.text;
      Result:=TXxmProjectCacheEntry.Create(Name,n,VarToStr(x.getAttribute('LoadCopy'))<>'0');
      Result.FSignature:=LowerCase(VarToStr(x.getAttribute('Signature')));
    finally
      y:=nil;
      x:=nil;
      xl:=nil;
      doc:=nil;
    end;
    i:=0;
    while (i<ProjectCacheSize) and not(ProjectCache[i]=nil) do inc(i);
    if (i=ProjectCacheSize) then i:=Grow;
    ProjectCache[i]:=Result;
   end
  else
    Result:=ProjectCache[i];
end;

procedure TXxmProjectCache.ReleaseProject(Name: WideString);
var
  i:integer;
begin
  i:=FindOpenProject(LowerCase(Name));
  //if i=-1 then raise?
  if not(i=-1) then FreeAndNil(ProjectCache[i]);
end;

procedure TXxmProjectCache.ClearAll;
var
  i:integer;
begin
  for i:=0 to ProjectCacheSize-1 do FreeAndNil(ProjectCache[i]);
  SetLength(ProjectCache,0);
  ProjectCacheSize:=0;
end;

initialization
  XxmProjectCache:=TXxmProjectCache.Create;
finalization
  //assert XxmProjectCache=nil by TerminateExtension
  FreeAndNil(XxmProjectCache);
end.
