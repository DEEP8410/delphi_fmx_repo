unit YandexOAuth;

interface

uses
  System.SysUtils, System.Classes, System.Net.URLClient, System.Net.HttpClient,
  System.JSON, FMX.WebBrowser, System.Threading, FMX.Platform, FMX.Types;

type
  /// <summary>
  /// Тип события для возврата полученного токена
  /// </summary>
  TOnTokenReceived = procedure(const AAccessToken, ARefreshToken: string; 
    AExpiresIn: Integer; const AError: string) of object;

  /// <summary>
  /// Класс для получения OAuth токена Яндекс
  /// Реализует механизм авторизации по инструкции: 
  /// https://yandex.ru/dev/id/doc/ru/codes/code-url
  /// </summary>
  TYandexOAuth = class
  private
    FClientID: string;
    FClientSecret: string;
    FRedirectURI: string;
    FWebBrowser: TWebBrowser;
    FOnTokenReceived: TOnTokenReceived;
    FCurrentTask: ITask;
    
    procedure HandleNavigation(const ASender: TObject; const AURL: string);
    function ExtractCodeFromURL(const AURL: string): string;
    function ExchangeCodeForToken(const ACode: string): string;
    procedure ParseTokenResponse(const AJSONResponse: string; out AAccessToken, 
      ARefreshToken: string; out AExpiresIn: Integer; out AError: string);
    procedure ShowAuthPage;
    procedure CloseWebBrowser;
    function URLEncode(const AValue: string): string;
  public
    /// <summary>
    /// Конструктор класса
    /// </summary>
    /// <param name="AClientID">Идентификатор приложения Яндекс</param>
    /// <param name="AClientSecret">Секретный ключ приложения</param>
    /// <param name="ARedirectURI">URI перенаправления (должен быть зарегистрирован в приложении Яндекс)</param>
    constructor Create(const AClientID, AClientSecret, ARedirectURI: string);
    
    /// <summary>
    /// Деструктор класса
    /// </summary>
    destructor Destroy; override;
    
    /// <summary>
    /// Запуск процесса получения токена
    /// </summary>
    /// <param name="AOnTokenReceived">Событие вызываемое после получения токена или ошибки</param>
    procedure GetToken(const AOnTokenReceived: TOnTokenReceived);
    
    /// <summary>
    /// Обновление токена используя refresh token
    /// </summary>
    /// <param name="ARefreshToken">Refresh токен полученный ранее</param>
    /// <param name="AOnTokenReceived">Событие вызываемое после получения токена или ошибки</param>
    procedure RefreshToken(const ARefreshToken: string; const AOnTokenReceived: TOnTokenReceived);
    
    /// <summary>
    /// Свойство для доступа к ClientID
    /// </summary>
    property ClientID: string read FClientID;
    
    /// <summary>
    /// Свойство для доступа к ClientSecret
    /// </summary>
    property ClientSecret: string read FClientSecret;
    
    /// <summary>
    /// Свойство для доступа к RedirectURI
    /// </summary>
    property RedirectURI: string read FRedirectURI;
  end;

implementation

{ TYandexOAuth }

constructor TYandexOAuth.Create(const AClientID, AClientSecret, ARedirectURI: string);
begin
  inherited Create;
  FClientID := AClientID;
  FClientSecret := AClientSecret;
  FRedirectURI := ARedirectURI;
  FWebBrowser := nil;
  FOnTokenReceived := nil;
end;

destructor TYandexOAuth.Destroy;
begin
  CloseWebBrowser;
  inherited;
end;

procedure TYandexOAuth.CloseWebBrowser;
begin
  if Assigned(FWebBrowser) then
  begin
    FWebBrowser.OnNavigate := nil;
    FWebBrowser.Visible := False;
    FreeAndNil(FWebBrowser);
  end;
end;

function TYandexOAuth.URLEncode(const AValue: string): string;
var
  i: Integer;
  ch: Char;
begin
  Result := '';
  for i := 1 to Length(AValue) do
  begin
    ch := AValue[i];
    case ch of
      'A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~':
        Result := Result + ch;
      ' ':
        Result := Result + '+';
    else
      Result := Result + '%' + IntToHex(Ord(ch), 2);
    end;
  end;
end;

procedure TYandexOAuth.ShowAuthPage;
var
  AuthURL: string;
begin
  // Формируем URL для авторизации согласно документации Яндекс
  // https://yandex.ru/dev/id/doc/ru/codes/code-url
  AuthURL := 'https://oauth.yandex.ru/authorize?' +
             'response_type=code&' +
             'client_id=' + FClientID + '&' +
             'redirect_uri=' + URLEncode(FRedirectURI) + '&' +
             'state=delphi_fmx_oauth';
  
  // Создаем веб-браузер для отображения страницы авторизации
  FWebBrowser := TWebBrowser.Create(nil);
  try
    FWebBrowser.Align := TAlignLayout.Client;
    FWebBrowser.Visible := True;
    FWebBrowser.OnNavigate := HandleNavigation;
    
    // Добавляем веб-браузер на главную форму приложения
    // Примечание: В реальном приложении нужно передавать ссылку на форму
    // Здесь предполагается что FWebBrowser будет добавлен на форму вручную
    // или используется модальное отображение
    
    FWebBrowser.Navigate(AuthURL);
  except
    on E: Exception do
    begin
      CloseWebBrowser;
      if Assigned(FOnTokenReceived) then
        FOnTokenReceived('', '', 0, 'Ошибка создания веб-браузера: ' + E.Message);
    end;
  end;
end;

procedure TYandexOAuth.HandleNavigation(const ASender: TObject; const AURL: string);
var
  Code: string;
begin
  // Проверяем, является ли текущий URL адресом перенаправления
  // Для события OnNavigate параметр AURL содержит новый URL
  if Pos(FRedirectURI, AURL) > 0 then
  begin
    // Извлекаем код авторизации из URL
    Code := ExtractCodeFromURL(AURL);
    
    if Code <> '' then
    begin
      // Закрываем веб-браузер
      CloseWebBrowser;
      
      // Обмениваем код на токен в фоновом потоке
      FCurrentTask := TTask.Run(procedure
      var
        AccessToken, RefreshToken, ErrorMsg: string;
        ExpiresIn: Integer;
        TokenResponse: string;
      begin
        try
          TokenResponse := ExchangeCodeForToken(Code);
          ParseTokenResponse(TokenResponse, AccessToken, RefreshToken, ExpiresIn, ErrorMsg);
          
          if Assigned(FOnTokenReceived) then
            TThread.Synchronize(nil, procedure
            begin
              FOnTokenReceived(AccessToken, RefreshToken, ExpiresIn, ErrorMsg);
            end);
        except
          on E: Exception do
          begin
            if Assigned(FOnTokenReceived) then
              TThread.Synchronize(nil, procedure
              begin
                FOnTokenReceived('', '', 0, 'Ошибка обмена кода на токен: ' + E.Message);
              end);
          end;
        end;
      end);
    end
    else
    begin
      // Код не найден, возможно ошибка авторизации
      CloseWebBrowser;
      if Assigned(FOnTokenReceived) then
        FOnTokenReceived('', '', 0, 'Не удалось получить код авторизации');
    end;
  end;
end;

function TYandexOAuth.ExtractCodeFromURL(const AURL: string): string;
var
  Params: TStringList;
  i: Integer;
begin
  Result := '';
  Params := TStringList.Create;
  try
    // Разбираем query параметры URL
    if Pos('?', AURL) > 0 then
    begin
      Params.Delimiter := '&';
      Params.StrictDelimiter := True;
      Params.DelimitedText := Copy(AURL, Pos('?', AURL) + 1, MaxInt);
      
      // Ищем параметр 'code'
      for i := 0 to Params.Count - 1 do
      begin
        if Pos('code=', Params[i]) = 1 then
        begin
          Result := Copy(Params[i], 6, MaxInt);
          Break;
        end;
      end;
    end;
  finally
    Params.Free;
  end;
end;

function TYandexOAuth.ExchangeCodeForToken(const ACode: string): string;
var
  HTTPClient: THTTPClient;
  Params: TStringList;
  Response: IHTTPResponse;
begin
  Result := '';
  HTTPClient := THTTPClient.Create;
  Params := TStringList.Create;
  try
    // Формируем параметры запроса для обмена кода на токен
    Params.Add('grant_type=authorization_code');
    Params.Add('code=' + ACode);
    Params.Add('client_id=' + FClientID);
    Params.Add('client_secret=' + FClientSecret);
    Params.Add('redirect_uri=' + URLEncode(FRedirectURI));
    
    // Отправляем POST запрос на сервер Яндекс
    Response := HTTPClient.Post('https://oauth.yandex.ru/token', Params);
    
    if Response.StatusCode = 200 then
      Result := Response.ContentAsString;
  finally
    Params.Free;
    HTTPClient.Free;
  end;
end;

procedure TYandexOAuth.ParseTokenResponse(const AJSONResponse: string; 
  out AAccessToken, ARefreshToken: string; out AExpiresIn: Integer; out AError: string);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
begin
  AAccessToken := '';
  ARefreshToken := '';
  AExpiresIn := 0;
  AError := '';
  
  if AJSONResponse = '' then
  begin
    AError := 'Пустой ответ от сервера';
    Exit;
  end;
  
  JSONValue := TJSONObject.ParseJSONValue(AJSONResponse);
  try
    if JSONValue is TJSONObject then
    begin
      JSONObject := TJSONObject(JSONValue);
      
      // Проверяем наличие ошибки
      if JSONObject.GetValue('error') <> nil then
      begin
        AError := JSONObject.GetValue('error').Value;
        if JSONObject.GetValue('error_description') <> nil then
          AError := AError + ': ' + JSONObject.GetValue('error_description').Value;
      end
      else
      begin
        // Извлекаем токен и данные
        if JSONObject.GetValue('access_token') <> nil then
          AAccessToken := JSONObject.GetValue('access_token').Value;
        
        if JSONObject.GetValue('refresh_token') <> nil then
          ARefreshToken := JSONObject.GetValue('refresh_token').Value;
        
        if JSONObject.GetValue('expires_in') <> nil then
          AExpiresIn := StrToIntDef(JSONObject.GetValue('expires_in').Value, 0);
      end;
    end
    else
    begin
      AError := 'Неверный формат ответа (ожидался JSON)';
    end;
  finally
    JSONValue.Free;
  end;
end;

procedure TYandexOAuth.GetToken(const AOnTokenReceived: TOnTokenReceived);
begin
  FOnTokenReceived := AOnTokenReceived;
  
  // Показываем страницу авторизации в веб-браузере
  ShowAuthPage;
end;

procedure TYandexOAuth.RefreshToken(const ARefreshToken: string; 
  const AOnTokenReceived: TOnTokenReceived);
var
  HTTPClient: THTTPClient;
  Params: TStringList;
  Response: IHTTPResponse;
  AccessToken, RefreshTokenNew, ErrorMsg: string;
  ExpiresIn: Integer;
begin
  FOnTokenReceived := AOnTokenReceived;
  
  HTTPClient := THTTPClient.Create;
  Params := TStringList.Create;
  try
    // Формируем параметры запроса для обновления токена
    Params.Add('grant_type=refresh_token');
    Params.Add('refresh_token=' + ARefreshToken);
    Params.Add('client_id=' + FClientID);
    Params.Add('client_secret=' + FClientSecret);
    
    // Отправляем POST запрос на сервер Яндекс
    Response := HTTPClient.Post('https://oauth.yandex.ru/token', Params);
    
    if Response.StatusCode = 200 then
    begin
      ParseTokenResponse(Response.ContentAsString, AccessToken, RefreshTokenNew, ExpiresIn, ErrorMsg);
      
      if Assigned(FOnTokenReceived) then
        FOnTokenReceived(AccessToken, RefreshTokenNew, ExpiresIn, ErrorMsg);
    end
    else
    begin
      if Assigned(FOnTokenReceived) then
        FOnTokenReceived('', '', 0, 'Ошибка HTTP: ' + IntToStr(Response.StatusCode));
    end;
  except
    on E: Exception do
    begin
      if Assigned(FOnTokenReceived) then
        FOnTokenReceived('', '', 0, 'Ошибка обновления токена: ' + E.Message);
    end;
  finally
    Params.Free;
    HTTPClient.Free;
  end;
end;

end.
