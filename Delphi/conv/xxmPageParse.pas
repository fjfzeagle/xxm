unit xxmPageParse;

interface

uses Classes;

type
  TXxmPageSection=(
    psHTML,
    psUses,               // [[@
    psDefinitions,        // [[:
    psHeader,             // [[!
    psBody,               // [[
    psFooter,             // [[_
    psSend,               // [[=
    psSendHTML,           // [[#
    psURLEncode,          // [[?
    psComment,            // [[/
    psParserParameter,    // [[*
    psExtra1,             // [[&
    psExtra2,             // [[%
    psExtra3,             // [[.
    psExtra4,             // [[,
    psExtra5,             // [[;
    psSquareBracketsOpen, // [[[]]
    psSquareBracketsClose // [[]]]
  );

//TODO: dynamic chars for use with AllSections

  TXxmLineNumbersMap=class(TObject)
  private
    LineNrs:array of record
      PasLineNr,XxmLineNr:word;
    end;
    LineNrsIndex,LineNrsSize,PasLineNr:integer;
    procedure Grow;
  public
    constructor Create;
    destructor Destroy; override;
    procedure MapLine(AdvancePasLines, XxmLineNr:integer);
    procedure Save(const FilePath:AnsiString);
    procedure Clear;
    procedure Load(const FilePath:AnsiString);
    function GetXxmLines(PasLineNr:integer):AnsiString;
  end;

  TXxmPageParserValues=(
    pvSend,
    pvSendClose,
    pvSendHTML,
    pvSendHTMLClose,
    pvURLEncode,
    pvURLEncodeClose,
    pvExtra1,pvExtra1Close,
    pvExtra2,pvExtra2Close,
    pvExtra3,pvExtra3Close,
    pvExtra4,pvExtra4Close,
    pvExtra5,pvExtra5Close,
    //add new above
    pv_Unknown
  );

  TXxmPageParserValueList=array[TXxmPageParserValues] of record
    Code:AnsiString;
    EOLs:integer;
  end;

  TXxmPageParser=class(TObject)
  private
    FData:AnsiString;
    SectionsCount,SectionsSize,TotalLines:integer;
    Sections:array of record
      Index,Length,LineNr:integer;
      SectionType:TXxmPageSection;
    end;
    FIndex:integer;
    FDefaultParserValues,FParserValues:TXxmPageParserValueList;
    procedure AddSection(Index,Length,LineNr:integer;ps:TXxmPageSection);
    function EOLs(Index: integer): integer;
    function LineHasTag(var x:integer;l:integer):integer;
  public
    constructor Create(const ParserValues:TXxmPageParserValueList);
    destructor Destroy; override;
    procedure Parse(Data:AnsiString);
    //function GetNext:;
    //function Done:boolean;
    function AllSections(ps:TXxmPageSection;map:TXxmLineNumbersMap):AnsiString;
    function BuildBody(map:TXxmLineNumbersMap):AnsiString;
  end;

const
  SectionParserValue:array[TXxmPageSection] of TXxmPageParserValues=(
    pv_Unknown,  //psHTML,
    pv_Unknown,  //psUses,
    pv_Unknown,  //psDefinitions,
    pv_Unknown,  //psHeader,
    pv_Unknown,  //psBody,
    pv_Unknown,  //psFooter,
    pvSend,      //psSend
    pvSendHTML,  //psSendHTML
    pvURLEncode, //psURLEncode
    pv_Unknown,  //psComment
    pv_Unknown,  //psParserParameter
    pvExtra1,    //psExtra1
    pvExtra2,    //psExtra2
    pvExtra3,    //psExtra3
    pvExtra4,    //psExtra4
    pvExtra5,    //psExtra5
    pv_Unknown,pv_Unknown //psSquareBrackets* etc
  );

implementation

uses SysUtils, Windows;

{ TXxmLineNumbersMap }

constructor TXxmLineNumbersMap.Create;
begin
  inherited;
  LineNrsIndex:=0;
  LineNrsSize:=0;
  PasLineNr:=1;
end;

destructor TXxmLineNumbersMap.Destroy;
begin
  SetLength(LineNrs,0);
  inherited;
end;

procedure TXxmLineNumbersMap.Clear;
begin
  LineNrsIndex:=0;
  //LineNrsSize:=0;
  PasLineNr:=1;
end;

procedure TXxmLineNumbersMap.Grow;
begin
  inc(LineNrsSize,$400);
  SetLength(LineNrs,LineNrsSize);
end;

procedure TXxmLineNumbersMap.MapLine(AdvancePasLines, XxmLineNr: integer);
begin
  if XxmLineNr<>0 then
   begin
    if LineNrsIndex=LineNrsSize then Grow;
    LineNrs[LineNrsIndex].PasLineNr:=PasLineNr;
    LineNrs[LineNrsIndex].XxmLineNr:=XxmLineNr;
    inc(LineNrsIndex);
   end;
  inc(PasLineNr,AdvancePasLines);
end;

procedure TXxmLineNumbersMap.Save(const FilePath: AnsiString);
var
  f:TFileStream;
begin
  SetFileAttributesA(PAnsiChar(FilePath),0);//strange, hidden files throw exception on overwrite
  f:=TFileStream.Create(FilePath,fmCreate);
  try
    f.Write(LineNrs[0],LineNrsIndex*4);
  finally
    f.Free;
  end;
  SetFileAttributesA(PAnsiChar(FilePath),FILE_ATTRIBUTE_HIDDEN);// or FILE_ATTRIBUTE_SYSTEM);//?
end;

procedure TXxmLineNumbersMap.Load(const FilePath: AnsiString);
var
  f:TFileStream;
  s:Int64;
begin
  PasLineNr:=1;
  f:=TFileStream.Create(FilePath,fmOpenRead);
  try
    s:=f.Size;
    LineNrsIndex:=s div 4;
    while LineNrsSize<LineNrsIndex do Grow;
    f.Read(LineNrs[0],s);
  finally
    f.Free;
  end;
end;

function TXxmLineNumbersMap.GetXxmLines(PasLineNr:integer):AnsiString;
var
  i:integer;
begin
  i:=0;
  Result:='';
  while (i<LineNrsIndex) and (LineNrs[i].PasLineNr<PasLineNr) do inc(i);
  if (i<LineNrsIndex) and (LineNrs[i].PasLineNr=PasLineNr) then
    while (i<LineNrsIndex) and (LineNrs[i].PasLineNr=PasLineNr) do
     begin
      if Result<>'' then Result:=Result+',';
      Result:=Result+IntToStr(LineNrs[i].XxmLineNr);
      inc(i);
     end
  else
    if i>0 then
     begin
      dec(i);
      Result:=IntToStr(LineNrs[i].XxmLineNr+PasLineNr-LineNrs[i].PasLineNr);
     end;
end;

{ TXxmPageParser }

constructor TXxmPageParser.Create(const ParserValues:TXxmPageParserValueList);
begin
  inherited Create;
  FData:='';
  SectionsCount:=0;
  SectionsSize:=0;
  FIndex:=0;
  FDefaultParserValues:=ParserValues;
  FParserValues:=FDefaultParserValues;
  //TODO: flag enable/disable keep line-numbers?
end;

destructor TXxmPageParser.Destroy;
begin
  SetLength(Sections,0);
  inherited;
end;

procedure TXxmPageParser.Parse(Data: AnsiString);
type
  TDelim=(dNone,dSquareB,dAngleB);
const
  CodeType_Normal=0;
  CodeType_String=1;
  CodeType_CommentA=2;
  CodeType_CommentB=3;
  CodeType_ParserParameters=4;
var
  a1,a2,b1,b2,bx,l,n1,n2,nx,sqd,CodeType,TagInCode:integer;
  Delim:TDelim;
  ps:TXxmPageSection;
begin
  SectionsCount:=0;
  SectionsSize:=0;
  //SetLength(Sections,0);
  FData:=Data;
  FIndex:=0;
  TagInCode:=0;
  l:=Length(FData);
  a1:=1;//counter warning
  a2:=1;
  n1:=1;
  nx:=1;
  while a2<=l do
   begin
    //search for an open tag
    n1:=nx;
    a1:=a2;
    Delim:=dNone;
    while (a2<=l)
      and not((Delim=dSquareB) and (FData[a2]='['))
      and not((Delim=dAngleB) and (FData[a2]='>')) do
     begin
      case char(FData[a2]) of
        '[':Delim:=dSquareB;
        '>':Delim:=dAngleB;
        #13,#10:
         begin
          inc(nx);
          if (FData[a2]=#13) and (a2<l) and (FData[a2+1]=#10) then inc(a2);
          if TagInCode=0 then
            Delim:=dNone
          else
           begin //make loop exit
            Delim:=dAngleB;
            a2:=TagInCode-1;
           end;
         end;
        else Delim:=dNone;
      end;
      inc(a2);
     end;
    b1:=a2+1;
    b2:=b1;
    if Delim=dAngleB then
     begin
      a2:=b1;//inc(a2);
      if TagInCode<>0 then
       begin
        inc(a2);
        TagInCode:=0;
       end;
     end;
    if (Delim<>dNone) and (b1<=l) then
     begin
      //open tag found, look for close tag (carefully: check strings and opening/closing braces and things)
      Delim:=dNone;
      sqd:=0;//square bracket depth
      CodeType:=CodeType_Normal;
      n2:=nx;
      case char(FData[b1]) of
        '[':ps:=psSquareBracketsOpen;
        ']':ps:=psSquareBracketsClose;
        '!':ps:=psHeader;
        '@':ps:=psUses;
        ':':ps:=psDefinitions;
        '_':ps:=psFooter;
        '#':ps:=psSendHTML;
        '=':ps:=psSend;
        '?':ps:=psURLEncode;
        '/':ps:=psComment;
        '*':
         begin
          ps:=psParserParameter;
          CodeType:=CodeType_ParserParameters;
         end;
        '&':ps:=psExtra1;
        '%':ps:=psExtra2;
        '.':ps:=psExtra3;
        ',':ps:=psExtra4;
        ';':ps:=psExtra5;
        //'&$%^+|;.,
        else ps:=psBody;
      end;
      while (b2<=l)
        and not((Delim=dSquareB) and (FData[b2]=']'))
        and not((Delim=dAngleB) and (FData[b2]='<')) do
       begin
        Delim:=dNone;
        case CodeType of
          CodeType_Normal:
            case char(FData[b2]) of
              '''':CodeType:=CodeType_String;
              '[':inc(sqd);
              ']':if sqd=0 then Delim:=dSquareB else dec(sqd);
              '{':CodeType:=CodeType_CommentA;
              //'}'
              '(':
                if (b2<l) and (FData[b2+1]='*') then
                  CodeType:=CodeType_CommentB;
              //')'
              '<':Delim:=dAngleB;
            end;
          CodeType_String:
            if char(FData[b2]) in ['''',#13,#10] then
              CodeType:=CodeType_Normal;
          CodeType_CommentA:
            if char(FData[b2])='}' then
              CodeType:=CodeType_Normal;
          CodeType_CommentB:
            if (char(FData[b2])=')') and (b2>1) and (FData[b2-1]='*') then
              CodeType:=CodeType_Normal;
          CodeType_ParserParameters:
            case char(FData[b2]) of
              '<':Delim:=dAngleB;
              ']':Delim:=dSquareB;
            end;
        end;
        if char(FData[b2]) in [#13,#10] then
         begin
          inc(nx);
          if (FData[b2]=#13) and (b2<l) and (FData[b2+1]=#10) then inc(b2);
          if (ps=psBody) and (CodeType=CodeType_Normal) then
           begin
            TagInCode:=LineHasTag(b2,l);
            if TagInCode<>0 then //make loop exit
             begin
              Delim:=dAngleB;
              dec(b2);
             end;
           end;
         end;
        inc(b2);
       end;
      if b2>l then
       begin
        //end reached
        AddSection(a1,a2-a1-1,n1,psHTML);
        AddSection(b1,b2-b1,n2,psBody);
        a1:=b2;
        a2:=b2;
       end
      else
        if ((Delim<>dNone) and (a2<l)) or (b2>l) then
         begin
          //close tag found also
          bx:=b1;
          case ps of
            psSquareBracketsOpen:
              if b2-b1=1 then Delim:=dSquareB else Delim:=dNone;
            psSquareBracketsClose:
              if b2-b1=1 then Delim:=dSquareB else Delim:=dNone;
            psBody:
              dec(bx);
          end;
          if (Delim<>dNone) or (b2>l) then
           begin
            AddSection(a1,a2-a1-1,n1,psHTML);
            case Delim of
              dSquareB:
               begin
                AddSection(bx+1,b2-bx-2,n2,ps);
                a2:=b2+1;
               end;
              dAngleB:
               begin
                inc(bx);
                AddSection(bx,b2-bx-1,n2,ps);
                a2:=b2;
               end;
            end;
           end
          else
            AddSection(a1,a2-a1,n1,psHTML);
          a1:=a2;
         end
        else
          a2:=l+1;
     end;
   end;
  AddSection(a1,l-a1+1,n1,psHTML);
  TotalLines:=nx;
end;

procedure TXxmPageParser.AddSection(Index, Length, LineNr: integer;
  ps: TXxmPageSection);
begin
  if (Length>0) or (ps=psParserParameter) then
   begin
    if SectionsCount=SectionsSize then
     begin
      inc(SectionsSize,$100);
      SetLength(Sections,SectionsSize);
     end;
    Sections[SectionsCount].Index:=Index;
    Sections[SectionsCount].Length:=Length;
    Sections[SectionsCount].LineNr:=LineNr;
    Sections[SectionsCount].SectionType:=ps;
    inc(SectionsCount);
   end;
end;

function TXxmPageParser.AllSections(ps:TXxmPageSection;map:TXxmLineNumbersMap): AnsiString;
var
  i,j,l:integer;
begin
  //get total length first
  l:=0;
  for i:=0 to SectionsCount-1 do
    if Sections[i].SectionType=ps then inc(l,Sections[i].Length);
  //allocate all memory needed in one go
  SetLength(Result,l);
  //and fill it
  j:=1;
  for i:=0 to SectionsCount-1 do
    if Sections[i].SectionType=ps then
     begin
      Move(PAnsiChar(@FData[Sections[i].Index])^,PAnsiChar(@Result[j])^,Sections[i].Length);
      inc(j,Sections[i].Length);
      map.MapLine(EOLs(i),Sections[i].LineNr);
     end;
end;

function TXxmPageParser.BuildBody(map:TXxmLineNumbersMap): AnsiString;
var
  ss:TStringStream;
  InSend,InString:boolean;
  SendCloseCode:AnsiString;
  SendCloseEOLs,l:integer;

  procedure OpenString;
  begin
    if not InString then
     begin
      ss.WriteString('''');
      InString:=true;
      inc(l);
     end;
  end;

  procedure CloseString;
  begin
    if InString then
     begin
      ss.WriteString('''');
      InString:=false;
      inc(l);
     end;
  end;

  procedure OpenSend(LineNr:integer);
  begin
    if not InSend then
     begin
      ss.WriteString('  '+StringReplace(FParserValues[pvSendHTML].Code,
        '$l',IntToStr(LineNr),[rfReplaceAll]));
      map.MapLine(FParserValues[pvSendHTML].EOLs,0);
      InSend:=true;

      SendCloseCode:=FParserValues[pvSendHTMLClose].Code;
      SendCloseEOLs:=FParserValues[pvSendHTMLClose].EOLs;
      InString:=false;//assert already false?
      l:=15;
     end;
  end;

  procedure CloseSend(LineNr:integer);
  begin
    if InSend then
     begin
      CloseString;
      ss.WriteString(StringReplace(SendCloseCode,
        '$l',IntToStr(LineNr+SendCloseEOLs),[rfReplaceAll])+#13#10);
      map.MapLine(1+SendCloseEOLs,0);
      InSend:=false;
     end;
  end;

  function CountEOLs(s:AnsiString):integer;
  var
    i,l:integer;
  begin
    Result:=0;
    l:=Length(s);
    for i:=1 to l-1 do if (s[i]=#13) and (s[i+1]=#10) then inc(Result);
  end;

  procedure ParseParserValue(const Code: string);
  var
    pv:TXxmPageParserValues;
  begin
    if Code='' then
      FParserValues:=FDefaultParserValues
    else
     begin
      pv:=pv_Unknown;
      case Code[1] of
        '=':pv:=pvSend;
        '#':pv:=pvSendHTML;
        '?':pv:=pvURLEncode;
        '&':pv:=pvExtra1;
        '%':pv:=pvExtra2;
        '.':pv:=pvExtra3;
        ',':pv:=pvExtra4;
        ';':pv:=pvExtra5;
        //else //TODO: parse parameter name
      end;
      if pv=pv_Unknown then raise Exception.Create('Unknown parse parameter');
      if Length(Code)=1 then
       begin
        FParserValues[pv]:=FDefaultParserValues[pv];
        pv:=Succ(pv);
        FParserValues[pv]:=FDefaultParserValues[pv];//close
       end
      else
       begin
        case Code[2] of
          '(':;
          ')':pv:=Succ(pv);//close
          else raise Exception.Create('Use "(" or ")" to define opening and closing code');
        end;
        FParserValues[pv].Code:=StringReplace(StringReplace(
          Copy(Code,3,Length(Code)-2),
          '$v',FParserValues[pv].Code,[rfReplaceAll]),
          '$d',FDefaultParserValues[pv].Code,[rfReplaceAll]);
        FParserValues[pv].EOLs:=CountEOLs(FParserValues[pv].Code);
       end;
     end;
  end;

  procedure ParseParserValuesMultiLine(Index: integer);
  var
    sl:TStringList;
    i:integer;
  begin
    sl:=TStringList.Create;
    try
      sl.Text:=Copy(FData,Sections[Index].Index,Sections[Index].Length);
      for i:=0 to sl.Count-1 do ParseParserValue(Trim(sl[i]));
    finally
      sl.Free;
    end;
  end;

var
  Section,p,q,r:integer;
  b:byte;
  pv:TXxmPageParserValues;
  p1,p2:PAnsiChar;
begin
  ss:=TStringStream.Create('');
  try
    InSend:=false;
    InString:=false;
    l:=0;
    for Section:=0 to SectionsCount-1 do
      try
        case Sections[Section].SectionType of
          psSquareBracketsOpen,psSquareBracketsClose:
           begin
            CloseSend(Sections[Section].LineNr);
            r:=FParserValues[pvSendHTML].EOLs;
            ss.WriteString('  '+StringReplace(FParserValues[pvSendHTML].Code,
              '$l',IntToStr(r+Sections[Section].LineNr),[rfReplaceAll]));
            if Sections[Section].SectionType=psSquareBracketsOpen then
              ss.WriteString('''[[''')
            else
              ss.WriteString(''']]''');
            inc(r,FParserValues[pvSendHTMLClose].EOLs);
            ss.WriteString(
              StringReplace(FParserValues[pvSendHTMLClose].Code,
              '$l',IntToStr(r+Sections[Section].LineNr),[rfReplaceAll])+#13#10);
            inc(r);
            map.MapLine(r,Sections[Section].LineNr);//assert EOLs(Section)=0
           end;
          psHTML:
           begin
            //convert into Context.SendHTML(
            p:=Sections[Section].Index;
            q:=p+Sections[Section].Length-1;
            OpenSend(Sections[Section].LineNr);
            while (p<=q) do
             begin
              if l>=78 then //setting?
               begin
                //CloseSend;
                CloseString;
                ss.WriteString('+'#13#10'    ');
                l:=0;
                map.MapLine(1,0);
               end;
              case char(FData[p]) of
                #0..#31:
                 begin
                  CloseString;
                  b:=byte(FData[p]);
                  //setting?
                  //ss.WriteString('#$'+IntToHex(b,2));
                  case byte(FData[p]) of
                    0..9:
                     begin
                      ss.WriteString('#'+AnsiChar($30+b));
                      inc(l,2);
                     end;
                    10..99:
                     begin
                      ss.WriteString('#'+AnsiChar($30+(b div 10))+
                        AnsiChar($30+(b mod 10)));
                      inc(l,3);
                     end;
                    100..255:
                     begin
                      ss.WriteString('#'+AnsiChar($30+(b div 100))+
                        AnsiChar($30+(b div 10 mod 10))+AnsiChar($30+(b mod 10)));
                      inc(l,4);
                     end;
                  end;
                 end;
                '''':
                 begin
                  OpenString;
                  ss.WriteString('''''');
                  inc(l,2);
                 end;
                else
                 begin
                  OpenString;
                  p1:=@FData[p];
                  p2:=CharNextA(p1);
                  r:=integer(p2)-integer(p1);
                  ss.Write(FData[p],r);
                  inc(l,r);
                  inc(p,r-1);
                 end;
              end;
              inc(p);
             end;
           end;
          psSend,psSendHTML,psURLEncode,
          psExtra1,psExtra2,psExtra3,psExtra4,psExtra5:
           begin
            CloseSend(Sections[Section].LineNr);
            pv:=SectionParserValue[Sections[Section].SectionType];
            r:=FParserValues[pv].EOLs;
            ss.WriteString('  '+StringReplace(FParserValues[pv].Code,
              '$l',IntToStr(r+Sections[Section].LineNr),[rfReplaceAll]));
            inc(r,EOLs(Section));
            ss.Write(FData[Sections[Section].Index],Sections[Section].Length);
            inc(pv);//pvXxxClose
            inc(r,FParserValues[pv].EOLs);
            ss.WriteString(StringReplace(FParserValues[pv].Code,
              '$l',IntToStr(r+Sections[Section].LineNr),[rfReplaceAll])+#13#10);
            inc(r);
            map.MapLine(r,Sections[Section].LineNr);
           end;
          psBody:
           begin
            CloseSend(Sections[Section].LineNr);
            ss.Write(FData[Sections[Section].Index],Sections[Section].Length);
            if (Sections[Section].Length<2) or not(
              (FData[Sections[Section].Index+Sections[Section].Length-2]=#13) and
              (FData[Sections[Section].Index+Sections[Section].Length-1]=#10)) then
             begin
              ss.WriteString(#13#10);
              map.MapLine(1+EOLs(Section),Sections[Section].LineNr);
             end
            else
              map.MapLine(EOLs(Section),Sections[Section].LineNr);
           end;
          psParserParameter:
           begin
            CloseSend(Sections[Section].LineNr);
            if (Sections[Section].Length>2) and (char(FData[Sections[Section].Index]) in [#13,#10,' ',#9]) then
              ParseParserValuesMultiLine(Section)
            else
              ParseParserValue(Copy(FData,Sections[Section].Index,Sections[Section].Length));
           end;
          //psComment: ignore
          //else
        end;
      except
        on e:Exception do
         begin
          e.Message:='['+IntToStr(Sections[Section].LineNr)+'] '+e.Message;
          raise;
         end;
      end;
    CloseSend(TotalLines);
    Result:=ss.DataString;
  finally
    ss.Free;
  end;
end;

function TXxmPageParser.EOLs(Index: integer): integer;
begin
  if Index=SectionsCount-1 then
    Result:=TotalLines-Sections[Index].LineNr
  else
    Result:=Sections[Index+1].LineNr-Sections[Index].LineNr;
end;

function TXxmPageParser.LineHasTag(var x:integer;l:integer):integer;
var
  a1,a2,a3:integer;
begin
  Result:=0;//default
  a1:=x+1;
  while (a1<=l) and (char(FData[a1]) in [#9,' ']) do inc(a1);
  if (a1<l) and (FData[a1]='<')
    and (char(FData[a1+1]) in ['A'..'Z','a'..'z','!','?']) then
   begin
    a2:=0;
    a3:=a1+2;
    while (a3<=l) and not(char(FData[a3]) in [#13,#10]) do
     begin
      if FData[a3]='>' then a2:=a3 else
        if (a2<>0) and not(FData[a3] in [#9,' ']) then a2:=0;
      inc(a3);
     end;
    if (a2>a1) and (FData[a2-1]<>'>') then
     begin
      Result:=a2;
      x:=a1;
     end;
   end;
end;

end.
