unit delphi_yajl;

interface

uses
   SysUtils, Windows, Classes,
   yajl_common, yajl_parse;

type
   PJSONRec = ^TJSONRec;
   TJSONRec = record
      Parent:        PJSONRec;
      Children:      array of PJSONRec;
      ChildrenCount: Integer;

      Key:           UTF8String;
      Value:         UTF8String;
   end;

   TJSONRecList = class(TList)
   public
      procedure Clear; override;

      function NewJSONRec: PJSONRec;
   end;

   TDelphiYajl = class
   private
      fDLLHandle: THandle;
      fRecList: TJSONRecList;
      fRootRec, fCurrentRec, fParentRec: PJSONRec;

      fParserConfig: yajl_parser_config;
      fCallbacks: yajl_callbacks;

      // yajl func imports
      yajl_alloc: Tyajl_alloc;
      yajl_free: Tyajl_free;
      yajl_parse: Tyajl_parse;
      yajl_parse_complete: Tyajl_parse_complete;
   protected
      function yajl_start_map: Integer; cdecl;
      function yajl_end_map: Integer; cdecl;
      function yajl_map_key(stringVal: PAnsiChar; stringLen: Cardinal): Integer; cdecl;
      function yajl_string(stringVal: PAnsiChar; stringLen: Cardinal): integer; cdecl;
      function yajl_number(numberVal: PAnsiChar; numberLen: Cardinal): integer; cdecl;
   public
      constructor Create;
      destructor Destroy; override;

      function ParseJSON(const aJSON: UTF8String): PJSONRec;
   end;

implementation

{ TDelphiYajl }

constructor TDelphiYajl.Create;
   procedure Bind(var p: Pointer; const aProcName: String);
   begin
      p := GetProcAddress(fDLLHandle, PChar(aProcName));
      if not Assigned(p) then
         raise Exception.CreateFmt('Could not bind %s in yajl.dll', [aProcName]);
   end;
begin
   fDLLHandle := LoadLibrary('yajl.dll');
   if fDLLHandle < 32 then
      raise Exception.Create('Could not load yajl.dll');

   fRecList := TJSONRecList.Create;

   Bind(@yajl_alloc,             'yajl_alloc');
   Bind(@yajl_free,              'yajl_free');
   Bind(@yajl_parse,             'yajl_parse');
   Bind(@yajl_parse_complete,    'yajl_parse_complete');
end;

destructor TDelphiYajl.Destroy;
begin
   fRecList.Free;

   if fDLLHandle >= 32 then
      FreeLibrary(fDLLHandle);

   inherited;
end;

function TDelphiYajl.ParseJSON(const aJSON: UTF8String): PJSONRec;
var
   s: RawByteString;
   h: yajl_handle;
begin
   s := aJSON;

   fParserConfig.allowComments := 1;
   fParserConfig.checkUTF8 := 0;

   // setup callbacks
//   fCallbacks.yajl_null := @TDelphiYajl.yajl_null;
//   fCallbacks.yajl_boolean := @TDelphiYajl.yajl_boolean;
//   fCallbacks.yajl_integer := @TDelphiYajl.yajl_integer;
//   fCallbacks.yajl_double := @TDelphiYajl.yajl_double;
   fCallbacks.yajl_number := @TDelphiYajl.yajl_number;
   fCallbacks.yajl_string := @TDelphiYajl.yajl_string;
   fCallbacks.yajl_start_map := @TDelphiYajl.yajl_start_map;
   fCallbacks.yajl_map_key := @TDelphiYajl.yajl_map_key;
   fCallbacks.yajl_end_map := @TDelphiYajl.yajl_end_map;
//   fCallbacks.yajl_start_array := @TDelphiYajl.yajl_start_array;
//   fCallbacks.yajl_end_array := @TDelphiYajl.yajl_end_array;

   h := yajl_alloc(@fCallbacks, @fParserConfig, nil, Self);

   fRootRec := fRecList.NewJSONRec;
   fRootRec.Key := 'Root';
   fCurrentRec := fRootRec;
   yajl_parse(h, PAnsiChar(s), Length(s));
   yajl_parse_complete(h);

   yajl_free(h);

   Result := fRootRec;
end;

function TDelphiYajl.yajl_start_map: Integer;
begin
   fParentRec := fCurrentRec;

   Result := 1;
end;

function TDelphiYajl.yajl_end_map: Integer;
begin
   if Assigned(fParentRec) then
      fParentRec := fParentRec.Parent;

   Result := 1;
end;

function TDelphiYajl.yajl_map_key(stringVal: PAnsiChar; stringLen: Cardinal): integer; cdecl;
var
   s: RawByteString;
begin
   fCurrentRec := fRecList.NewJSONRec;
   fCurrentRec.Parent := fParentRec;

   Inc(fParentRec.ChildrenCount);
   SetLength(fParentRec.Children, fParentRec.ChildrenCount);
   fParentRec.Children[fParentRec.ChildrenCount - 1] := fCurrentRec;

   s := RawByteString(stringVal);
   SetLength(s, stringLen);
   fCurrentRec.Key := UTF8string(s);

   Result := 1;
end;

function TDelphiYajl.yajl_string(stringVal: PAnsiChar; stringLen: Cardinal): integer; cdecl;
var
   s: RawByteString;
begin
   s := RawByteString(stringVal);
   SetLength(s, stringLen);
   fCurrentRec.Value := s;

   Result := 1;
end;

function TDelphiYajl.yajl_number(numberVal: PAnsiChar; numberLen: Cardinal): integer; cdecl;
begin
   Result := yajl_string(numberVal, numberLen);
end;

{ TJSONRecList }

procedure TJSONRecList.Clear;
var
   i: Integer;
begin
   for i := 0 to Self.Count - 1 do
      Dispose(PJSONRec(Self.Get(i)));

   inherited;
end;

function TJSONRecList.NewJSONRec: PJSONRec;
begin
   New(Result);
   Result.ChildrenCount := 0;
   Self.Add(Result);
end;

end.
