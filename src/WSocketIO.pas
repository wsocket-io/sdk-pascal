{*
  wSocket Pascal/Delphi SDK — Realtime Pub/Sub client with Presence, History, and Push.

  Usage:
    Client := TWSocketClient.Create('ws://localhost:9001', 'your-api-key');
    Client.Connect;
    Ch := Client.PubSub.Channel('chat');
    Ch.Subscribe(MyCallback);
    Ch.Publish('{"text":"hello"}');
*}
unit WSocketIO;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, fphttpclient, opensslsockets,
  ssockets, syncobjs;

type
  { Forward declarations }
  TWSocketClient = class;
  TWSocketChannel = class;
  TWSocketPresence = class;

  { ─── Types ─────────────────────────────────────────────── }

  TMessageMeta = record
    Id: string;
    Channel: string;
    Timestamp: Int64;
  end;

  TPresenceMember = record
    ClientId: string;
    Data: string;
    JoinedAt: Int64;
  end;

  THistoryMessage = record
    Id: string;
    Channel: string;
    Data: string;
    PublisherId: string;
    Timestamp: Int64;
    Sequence: Int64;
  end;

  THistoryResult = record
    Channel: string;
    Messages: array of THistoryMessage;
    HasMore: Boolean;
  end;

  TWSocketOptions = record
    AutoReconnect: Boolean;
    MaxReconnectAttempts: Integer;
    ReconnectDelay: Integer; // ms
    Token: string;
    Recover: Boolean;
  end;

  { Callback types }
  TMessageCallback = procedure(const Data: string; const Meta: TMessageMeta) of object;
  THistoryCallback = procedure(const Result: THistoryResult) of object;
  TPresenceCallback = procedure(const Member: TPresenceMember) of object;
  TMembersCallback = procedure(const Members: array of TPresenceMember) of object;
  TConnectCallback = procedure of object;
  TDisconnectCallback = procedure(Code: Integer) of object;
  TErrorCallback = procedure(const Msg: string) of object;

  { ─── Presence ──────────────────────────────────────────── }

  TWSocketPresence = class
  private
    FChannelName: string;
    FSendFn: procedure(const Msg: string) of object;
    FOnEnterCb: TPresenceCallback;
    FOnLeaveCb: TPresenceCallback;
    FOnUpdateCb: TPresenceCallback;
    FOnMembersCb: TMembersCallback;
  public
    constructor Create(const AChannel: string; ASendFn: procedure(const Msg: string) of object);

    procedure Enter(const Data: string = '');
    procedure Leave;
    procedure Update(const Data: string);
    procedure Get;

    procedure HandleEvent(const Action: string; AData: TJSONObject);

    property OnEnter: TPresenceCallback read FOnEnterCb write FOnEnterCb;
    property OnLeave: TPresenceCallback read FOnLeaveCb write FOnLeaveCb;
    property OnUpdate: TPresenceCallback read FOnUpdateCb write FOnUpdateCb;
    property OnMembers: TMembersCallback read FOnMembersCb write FOnMembersCb;
  end;

  { ─── Channel ───────────────────────────────────────────── }

  TWSocketChannel = class
  private
    FName: string;
    FSendFn: procedure(const Msg: string) of object;
    FMessageCb: TMessageCallback;
    FHistoryCb: THistoryCallback;
    FPresence: TWSocketPresence;
  public
    constructor Create(const AName: string; ASendFn: procedure(const Msg: string) of object);
    destructor Destroy; override;

    procedure Subscribe(Callback: TMessageCallback = nil);
    procedure Unsubscribe;
    procedure Publish(const Data: string; Persist: Boolean = False);
    procedure History(Limit: Integer = 0; Before: Int64 = 0; After: Int64 = 0; const Direction: string = '');

    procedure HandleMessage(const Data: string; const Meta: TMessageMeta);
    procedure HandleHistory(const Result: THistoryResult);

    property Name: string read FName;
    property Presence: TWSocketPresence read FPresence;
    property OnMessage: TMessageCallback read FMessageCb write FMessageCb;
    property OnHistory: THistoryCallback read FHistoryCb write FHistoryCb;
  end;

  { ─── PubSub Namespace ─────────────────────────────────── }

  TWSocketPubSub = class
  private
    FClient: TWSocketClient;
  public
    constructor Create(AClient: TWSocketClient);
    function Channel(const Name: string): TWSocketChannel;
  end;

  { ─── Push Client ───────────────────────────────────────── }

  TWSocketPush = class
  private
    FBaseUrl: string;
    FToken: string;
    FAppId: string;
    function DoPost(const Path, Body: string): string;
    function DoRequest(const Method, Url: string): string;
  public
    constructor Create(const ABaseUrl, AToken, AAppId: string);

    procedure RegisterFCM(const DeviceToken, MemberId: string);
    procedure RegisterAPNs(const DeviceToken, MemberId: string);
    procedure SendToMember(const MemberId, Payload: string);
    procedure Broadcast(const Payload: string);
    procedure Unregister(const MemberId: string; const Platform: string = '');
    procedure DeleteSubscription(const SubscriptionId: string);
    procedure AddChannel(const SubscriptionId, Channel: string);
    procedure RemoveChannel(const SubscriptionId, Channel: string);
    function GetVapidKey: string;
    function ListSubscriptions(const MemberId: string): string;
  end;

  { ─── Client ────────────────────────────────────────────── }

  TWSocketClient = class
  private
    FUrl: string;
    FApiKey: string;
    FOptions: TWSocketOptions;
    FChannels: TStringList;
    FSubscribed: TStringList;
    FLastMessageTs: Int64;
    FReconnectAttempts: Integer;
    FConnected: Boolean;
    FPubSub: TWSocketPubSub;
    FOnConnectCb: TConnectCallback;
    FOnDisconnectCb: TDisconnectCallback;
    FOnErrorCb: TErrorCallback;

    procedure SendRaw(const Msg: string);
    procedure HandleRawMessage(const Raw: string);
    procedure MaybeReconnect;
  public
    constructor Create(const AUrl, AApiKey: string);
    constructor Create(const AUrl, AApiKey: string; const AOptions: TWSocketOptions);
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;
    function GetChannel(const Name: string): TWSocketChannel;

    function ConfigurePush(const BaseUrl, Token, AppId: string): TWSocketPush;

    property Connected: Boolean read FConnected;
    property PubSub: TWSocketPubSub read FPubSub;
    property OnConnect: TConnectCallback read FOnConnectCb write FOnConnectCb;
    property OnDisconnect: TDisconnectCallback read FOnDisconnectCb write FOnDisconnectCb;
    property OnError: TErrorCallback read FOnErrorCb write FOnErrorCb;
  end;

  function DefaultOptions: TWSocketOptions;

implementation

function DefaultOptions: TWSocketOptions;
begin
  Result.AutoReconnect := True;
  Result.MaxReconnectAttempts := 10;
  Result.ReconnectDelay := 1000;
  Result.Token := '';
  Result.Recover := True;
end;

function GenerateUUID: string;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := GUIDToString(G);
  Result := Copy(Result, 2, Length(Result) - 2); // Remove braces
end;

{ ─── TWSocketPresence ────────────────────────────────────── }

constructor TWSocketPresence.Create(const AChannel: string;
  ASendFn: procedure(const Msg: string) of object);
begin
  inherited Create;
  FChannelName := AChannel;
  FSendFn := ASendFn;
end;

procedure TWSocketPresence.Enter(const Data: string);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'presence.enter');
    J.Add('channel', FChannelName);
    if Data <> '' then
      J.Add('data', GetJSON(Data));
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketPresence.Leave;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'presence.leave');
    J.Add('channel', FChannelName);
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketPresence.Update(const Data: string);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'presence.update');
    J.Add('channel', FChannelName);
    J.Add('data', GetJSON(Data));
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketPresence.Get;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'presence.get');
    J.Add('channel', FChannelName);
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketPresence.HandleEvent(const Action: string; AData: TJSONObject);
var
  M: TPresenceMember;
  Arr: TJSONArray;
  Members: array of TPresenceMember;
  I: Integer;
begin
  if (Action = 'presence.enter') and Assigned(FOnEnterCb) then begin
    M.ClientId := AData.Get('clientId', '');
    M.Data := AData.Get('data', TJSONObject.Create).AsJSON;
    M.JoinedAt := AData.Get('joinedAt', Int64(0));
    FOnEnterCb(M);
  end
  else if (Action = 'presence.leave') and Assigned(FOnLeaveCb) then begin
    M.ClientId := AData.Get('clientId', '');
    M.Data := AData.Get('data', TJSONObject.Create).AsJSON;
    M.JoinedAt := AData.Get('joinedAt', Int64(0));
    FOnLeaveCb(M);
  end
  else if (Action = 'presence.update') and Assigned(FOnUpdateCb) then begin
    M.ClientId := AData.Get('clientId', '');
    M.Data := AData.Get('data', TJSONObject.Create).AsJSON;
    M.JoinedAt := AData.Get('joinedAt', Int64(0));
    FOnUpdateCb(M);
  end
  else if (Action = 'presence.members') and Assigned(FOnMembersCb) then begin
    Arr := AData.Get('members', TJSONArray.Create) as TJSONArray;
    SetLength(Members, Arr.Count);
    for I := 0 to Arr.Count - 1 do begin
      Members[I].ClientId := Arr.Objects[I].Get('clientId', '');
      Members[I].Data := Arr.Objects[I].Get('data', TJSONObject.Create).AsJSON;
      Members[I].JoinedAt := Arr.Objects[I].Get('joinedAt', Int64(0));
    end;
    FOnMembersCb(Members);
  end;
end;

{ ─── TWSocketChannel ─────────────────────────────────────── }

constructor TWSocketChannel.Create(const AName: string;
  ASendFn: procedure(const Msg: string) of object);
begin
  inherited Create;
  FName := AName;
  FSendFn := ASendFn;
  FPresence := TWSocketPresence.Create(AName, ASendFn);
end;

destructor TWSocketChannel.Destroy;
begin
  FPresence.Free;
  inherited Destroy;
end;

procedure TWSocketChannel.Subscribe(Callback: TMessageCallback);
var
  J: TJSONObject;
begin
  if Assigned(Callback) then
    FMessageCb := Callback;
  J := TJSONObject.Create;
  try
    J.Add('action', 'subscribe');
    J.Add('channel', FName);
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketChannel.Unsubscribe;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'unsubscribe');
    J.Add('channel', FName);
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
  FMessageCb := nil;
end;

procedure TWSocketChannel.Publish(const Data: string; Persist: Boolean);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'publish');
    J.Add('channel', FName);
    J.Add('data', GetJSON(Data));
    J.Add('id', GenerateUUID);
    if Persist then
      J.Add('persist', True);
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketChannel.History(Limit: Integer; Before: Int64; After: Int64; const Direction: string);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('action', 'history');
    J.Add('channel', FName);
    if Limit > 0 then J.Add('limit', Limit);
    if Before > 0 then J.Add('before', Before);
    if After > 0 then J.Add('after', After);
    if Direction <> '' then J.Add('direction', Direction);
    FSendFn(J.AsJSON);
  finally
    J.Free;
  end;
end;

procedure TWSocketChannel.HandleMessage(const Data: string; const Meta: TMessageMeta);
begin
  if Assigned(FMessageCb) then
    FMessageCb(Data, Meta);
end;

procedure TWSocketChannel.HandleHistory(const Result: THistoryResult);
begin
  if Assigned(FHistoryCb) then
    FHistoryCb(Result);
end;

{ ─── TWSocketPubSub ──────────────────────────────────────── }

constructor TWSocketPubSub.Create(AClient: TWSocketClient);
begin
  inherited Create;
  FClient := AClient;
end;

function TWSocketPubSub.Channel(const Name: string): TWSocketChannel;
begin
  Result := FClient.GetChannel(Name);
end;

{ ─── TWSocketPush ────────────────────────────────────────── }

constructor TWSocketPush.Create(const ABaseUrl, AToken, AAppId: string);
begin
  inherited Create;
  FBaseUrl := ABaseUrl;
  FToken := AToken;
  FAppId := AAppId;
end;

function TWSocketPush.DoPost(const Path, Body: string): string;
var
  HTTP: TFPHTTPClient;
  SS: TStringStream;
begin
  HTTP := TFPHTTPClient.Create(nil);
  SS := TStringStream.Create(Body);
  try
    HTTP.AddHeader('Authorization', 'Bearer ' + FToken);
    HTTP.AddHeader('X-App-Id', FAppId);
    HTTP.AddHeader('Content-Type', 'application/json');
    HTTP.RequestBody := SS;
    Result := HTTP.Post(FBaseUrl + '/api/push/' + Path);
  finally
    SS.Free;
    HTTP.Free;
  end;
end;

function TWSocketPush.DoRequest(const Method, Url: string): string;
var
  HTTP: TFPHTTPClient;
  RS: TStringStream;
begin
  HTTP := TFPHTTPClient.Create(nil);
  RS := TStringStream.Create('');
  try
    HTTP.AddHeader('Authorization', 'Bearer ' + FToken);
    HTTP.AddHeader('X-App-Id', FAppId);
    HTTP.AddHeader('Content-Type', 'application/json');
    HTTP.HTTPMethod(Method, Url, RS, []);
    Result := RS.DataString;
  finally
    RS.Free;
    HTTP.Free;
  end;
end;

procedure TWSocketPush.RegisterFCM(const DeviceToken, MemberId: string);
begin
  DoPost('register', '{"memberId":"' + MemberId + '","platform":"fcm","subscription":{"deviceToken":"' + DeviceToken + '"}}');
end;

procedure TWSocketPush.RegisterAPNs(const DeviceToken, MemberId: string);
begin
  DoPost('register', '{"memberId":"' + MemberId + '","platform":"apns","subscription":{"deviceToken":"' + DeviceToken + '"}}');
end;

procedure TWSocketPush.SendToMember(const MemberId, Payload: string);
begin
  DoPost('send', '{"memberId":"' + MemberId + '","payload":' + Payload + '}');
end;

procedure TWSocketPush.Broadcast(const Payload: string);
begin
  DoPost('broadcast', '{"payload":' + Payload + '}');
end;

procedure TWSocketPush.Unregister(const MemberId: string; const Platform: string);
var
  Body: string;
begin
  Body := '{"memberId":"' + MemberId + '"';
  if Platform <> '' then
    Body := Body + ',"platform":"' + Platform + '"';
  Body := Body + '}';
  DoPost('unregister', Body);
end;

procedure TWSocketPush.DeleteSubscription(const SubscriptionId: string);
begin
  DoRequest('DELETE', FBaseUrl + '/api/push/subscriptions/' + SubscriptionId);
end;

procedure TWSocketPush.AddChannel(const SubscriptionId, Channel: string);
begin
  DoPost('channels/add', '{"memberId":"' + SubscriptionId + '","channel":"' + Channel + '"}');
end;

procedure TWSocketPush.RemoveChannel(const SubscriptionId, Channel: string);
begin
  DoPost('channels/remove', '{"memberId":"' + SubscriptionId + '","channel":"' + Channel + '"}');
end;

function TWSocketPush.GetVapidKey: string;
begin
  Result := DoRequest('GET', FBaseUrl + '/api/push/vapid-key');
end;

function TWSocketPush.ListSubscriptions(const MemberId: string): string;
begin
  Result := DoRequest('GET', FBaseUrl + '/api/push/subscriptions?memberId=' + MemberId);
end;

{ ─── TWSocketClient ──────────────────────────────────────── }

constructor TWSocketClient.Create(const AUrl, AApiKey: string);
begin
  Create(AUrl, AApiKey, DefaultOptions);
end;

constructor TWSocketClient.Create(const AUrl, AApiKey: string; const AOptions: TWSocketOptions);
begin
  inherited Create;
  FUrl := AUrl;
  FApiKey := AApiKey;
  FOptions := AOptions;
  FChannels := TStringList.Create;
  FChannels.OwnsObjects := True;
  FSubscribed := TStringList.Create;
  FLastMessageTs := 0;
  FReconnectAttempts := 0;
  FConnected := False;
  FPubSub := TWSocketPubSub.Create(Self);
end;

destructor TWSocketClient.Destroy;
begin
  FPubSub.Free;
  FSubscribed.Free;
  FChannels.Free;
  inherited Destroy;
end;

procedure TWSocketClient.Connect;
begin
  { WebSocket connection implementation depends on the WebSocket library used.
    For Indy: use TIdHTTP with WebSocket upgrade.
    For sgcWebSockets: use TsgcWebSocketClient.
    This is a stub — override or extend for your specific WebSocket library. }
  FConnected := True;
  FReconnectAttempts := 0;
  if Assigned(FOnConnectCb) then
    FOnConnectCb;
end;

procedure TWSocketClient.Disconnect;
begin
  FConnected := False;
end;

function TWSocketClient.GetChannel(const Name: string): TWSocketChannel;
var
  Idx: Integer;
begin
  Idx := FChannels.IndexOf(Name);
  if Idx >= 0 then
    Result := FChannels.Objects[Idx] as TWSocketChannel
  else begin
    Result := TWSocketChannel.Create(Name, @SendRaw);
    FChannels.AddObject(Name, Result);
  end;
end;

function TWSocketClient.ConfigurePush(const BaseUrl, Token, AppId: string): TWSocketPush;
begin
  Result := TWSocketPush.Create(BaseUrl, Token, AppId);
end;

procedure TWSocketClient.SendRaw(const Msg: string);
begin
  if not FConnected then Exit;
  { Send via WebSocket — implementation depends on WebSocket library used }
end;

procedure TWSocketClient.HandleRawMessage(const Raw: string);
var
  J: TJSONObject;
  Action, ChName: string;
  Ch: TWSocketChannel;
  Meta: TMessageMeta;
  Ts: Int64;
  Arr: TJSONArray;
  HR: THistoryResult;
  I, Idx: Integer;
begin
  try
    J := GetJSON(Raw) as TJSONObject;
    try
      Action := J.Get('action', '');
      ChName := J.Get('channel', '');

      if Action = 'message' then begin
        Idx := FChannels.IndexOf(ChName);
        if Idx < 0 then Exit;
        Ch := FChannels.Objects[Idx] as TWSocketChannel;
        Ts := J.Get('timestamp', FLastMessageTs);
        if Ts > FLastMessageTs then FLastMessageTs := Ts;
        Meta.Id := J.Get('id', '');
        Meta.Channel := ChName;
        Meta.Timestamp := Ts;
        Ch.HandleMessage(J.Get('data', TJSONObject.Create).AsJSON, Meta);
      end
      else if Action = 'subscribed' then begin
        if FSubscribed.IndexOf(ChName) < 0 then
          FSubscribed.Add(ChName);
      end
      else if Action = 'unsubscribed' then begin
        Idx := FSubscribed.IndexOf(ChName);
        if Idx >= 0 then FSubscribed.Delete(Idx);
      end
      else if Action = 'history' then begin
        Idx := FChannels.IndexOf(ChName);
        if Idx < 0 then Exit;
        Ch := FChannels.Objects[Idx] as TWSocketChannel;
        Arr := J.Get('messages', TJSONArray.Create) as TJSONArray;
        HR.Channel := ChName;
        SetLength(HR.Messages, Arr.Count);
        HR.HasMore := J.Get('hasMore', False);
        for I := 0 to Arr.Count - 1 do begin
          HR.Messages[I].Id := Arr.Objects[I].Get('id', '');
          HR.Messages[I].Channel := ChName;
          HR.Messages[I].Data := Arr.Objects[I].Get('data', TJSONObject.Create).AsJSON;
          HR.Messages[I].PublisherId := Arr.Objects[I].Get('publisherId', '');
          HR.Messages[I].Timestamp := Arr.Objects[I].Get('timestamp', Int64(0));
          HR.Messages[I].Sequence := Arr.Objects[I].Get('sequence', Int64(0));
        end;
        Ch.HandleHistory(HR);
      end
      else if (Action = 'presence.enter') or (Action = 'presence.leave') or
              (Action = 'presence.update') or (Action = 'presence.members') then begin
        Idx := FChannels.IndexOf(ChName);
        if Idx < 0 then Exit;
        Ch := FChannels.Objects[Idx] as TWSocketChannel;
        Ch.Presence.HandleEvent(Action, J);
      end
      else if Action = 'error' then begin
        if Assigned(FOnErrorCb) then
          FOnErrorCb(J.Get('error', 'Unknown error'));
      end;
    finally
      J.Free;
    end;
  except
    on E: Exception do
      if Assigned(FOnErrorCb) then
        FOnErrorCb(E.Message);
  end;
end;

procedure TWSocketClient.MaybeReconnect;
begin
  if not FOptions.AutoReconnect then Exit;
  if FReconnectAttempts >= FOptions.MaxReconnectAttempts then Exit;
  Inc(FReconnectAttempts);
  { Schedule reconnection after delay — implementation depends on threading approach }
end;

end.
