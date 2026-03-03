# wSocket SDK for Pascal / Delphi

Official Pascal/Delphi SDK for wSocket — realtime pub/sub, presence, history, and push notifications.

## Installation

### Delphi / Lazarus

Copy `src/WSocketIO.pas` to your project and add it to your uses clause:

```pascal
uses WSocketIO;
```

### Boss (Delphi Package Manager)

```bash
boss install wsocket-io/sdk-pascal
```

## Quick Start

```pascal
uses WSocketIO;

var
  Client: TWSocketClient;
  Channel: TWSocketChannel;
begin
  Client := TWSocketClient.Create('wss://node00.wsocket.online', 'your-api-key');
  
  Client.OnConnect := procedure
  begin
    WriteLn('Connected!');
  end;
  
  Client.Connect;

  Channel := Client.PubSub.Channel('chat');

  Channel.Subscribe(procedure(const Data: string; const Meta: TMessageMeta)
  begin
    WriteLn('Received: ', Data);
  end);

  Channel.Publish('{"text": "Hello from Pascal!"}');
end;
```

## Presence

```pascal
var
  Channel: TWSocketChannel;
begin
  Channel := Client.PubSub.Channel('room');

  Channel.Presence.Enter('{"name": "Alice"}');

  Channel.Presence.OnEnter := procedure(const Member: TPresenceMember)
  begin
    WriteLn(Member.ClientId, ' entered');
  end;

  Channel.Presence.OnLeave := procedure(const Member: TPresenceMember)
  begin
    WriteLn(Member.ClientId, ' left');
  end;

  Channel.Presence.Get;
end;
```

## History

```pascal
Channel.History(50);
Channel.OnHistory := procedure(const Result: THistoryResult)
var
  Msg: THistoryMessage;
begin
  for Msg in Result.Messages do
    WriteLn(Msg.PublisherId, ': ', Msg.Data);
end;
```

## Push Notifications

```pascal
var
  Push: TWSocketPush;
begin
  Push := TWSocketPush.Create('https://node00.wsocket.online', 'secret', 'app1');

  Push.RegisterFCM('device-token', 'user-123');
  Push.SendToMember('user-123', '{"title":"Hello","body":"World"}');
  Push.Broadcast('{"title":"News","body":"Update available"}');
end;
```

## Requirements

- Delphi 10.3+ or Free Pascal 3.2+
- Indy (TIdHTTP) or Synapse for HTTP/WebSocket

## License

MIT
