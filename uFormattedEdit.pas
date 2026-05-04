unit uFormattedEdit;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Messaging, FMX.Types, FMX.Controls, FMX.StdCtrls, FMX.Edit, FMX.Platform,
  FMX.Clipboard;

type
  /// <summary>
  /// Компонент TEdit для ввода положительных дробных чисел в формате ##.#
  /// (две цифры целой части, запятая, одна цифра дробной части)
  /// Оптимизирован для работы с виртуальной клавиатурой Android
  /// </summary>
  TFormattedEdit = class(TEdit)
  private
    FMaxValue: Double;
    FMinValue: Double;
    FOldText: string;
    FIsUpdating: Boolean;
    procedure SetMaxValue(const Value: Double);
    procedure SetMinValue(const Value: Double);
    procedure OnTextChanged(Sender: TObject);
    procedure FilterText(var AText: string);
    function IsValidFormat(const AText: string): Boolean;
    function IsCompleteFormat(const AText: string): Boolean;
  protected
    procedure KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState); override;
    procedure Change; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// Проверяет, является ли текущее значение корректным числом в полном формате
    /// </summary>
    function IsValid: Boolean;
    /// <summary>
    /// Возвращает числовое значение текста
    /// </summary>
    function TryGetValue(out Value: Double): Boolean;
    property Value: Double read GetNumericValue;
  published
    property Text stored True;
    property MaxValue: Double read FMaxValue write SetMaxValue default 99.9;
    property MinValue: Double read FMinValue write SetMinValue default 0.0;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Samples', [TFormattedEdit]);
end;

{ TFormattedEdit }

constructor TFormattedEdit.Create(AOwner: TComponent);
begin
  inherited;
  FMaxValue := 99.9;
  FMinValue := 0.0;
  FOldText := '';
  FIsUpdating := False;
  Text := '';
  
  // Настройки для Android - числовая клавиатура
  InputType := TInputType.Number;
  
  // Подписываемся на изменение текста для обработки вставки и виртуальной клавиатуры
  OnChange := OnTextChanged;
end;

destructor TFormattedEdit.Destroy;
begin
  inherited;
end;

procedure TFormattedEdit.Change;
begin
  inherited;
end;

procedure TFormattedEdit.OnTextChanged(Sender: TObject);
var
  NewText: string;
  CaretPos: Integer;
begin
  if FIsUpdating then
    Exit;
  
  NewText := Text;
  
  // Если текст не изменился, выходим
  if NewText = FOldText then
    Exit;
  
  // Сохраняем позицию курсора
  CaretPos := SelStart;
  
  // Фильтруем текст
  FilterText(NewText);
  
  // Если после фильтрации текст изменился, обновляем
  if NewText <> Text then
  begin
    FIsUpdating := True;
    try
      Text := NewText;
      // Устанавливаем курсор в конец
      SelStart := Length(Text);
      SelLength := 0;
    finally
      FIsUpdating := False;
    end;
  end;
  
  FOldText := Text;
end;

procedure TFormattedEdit.FilterText(var AText: string);
var
  CleanText: string;
  IntPart, FracPart: string;
  SepPos: Integer;
  i: Integer;
  Ch: Char;
begin
  if AText = '' then
    Exit;
  
  // Шаг 1: Очищаем от недопустимых символов
  CleanText := '';
  for i := 1 to Length(AText) do
  begin
    Ch := AText[i];
    // Разрешаем только цифры и запятую/точку
    if (Ch in ['0'..'9']) or (Ch = ',') or (Ch = '.') then
      CleanText := CleanText + Ch;
  end;
  
  // Шаг 2: Заменяем точку на запятую
  CleanText := StringReplace(CleanText, '.', ',', [rfReplaceAll]);
  
  // Шаг 3: Обрабатываем разделитель (запятую)
  SepPos := Pos(',', CleanText);
  if SepPos > 0 then
  begin
    // Берем часть до первой запятой как целую часть
    IntPart := Copy(CleanText, 1, SepPos - 1);
    
    // Всё после запятой - потенциальная дробная часть
    FracPart := Copy(CleanText, SepPos + 1, MaxInt);
    
    // Удаляем все дополнительные запятые из дробной части, оставляем только цифры
    var PureFrac := '';
    for i := 1 to Length(FracPart) do
      if FracPart[i] in ['0'..'9'] then
        PureFrac := PureFrac + FracPart[i];
    
    // Формируем результат
    if PureFrac <> '' then
      CleanText := IntPart + ',' + PureFrac
    else
      CleanText := IntPart;
  end;
  
  // Шаг 4: Ограничиваем целую часть двумя цифрами
  if SepPos > 0 then
    IntPart := Copy(CleanText, 1, SepPos - 1)
  else
    IntPart := CleanText;
  
  if Length(IntPart) > 2 then
    IntPart := Copy(IntPart, 1, 2);
  
  // Шаг 5: Формируем итоговую строку с ограниченной дробной частью
  if SepPos > 0 then
  begin
    if Length(CleanText) > SepPos then
      FracPart := Copy(CleanText, SepPos + 1, MaxInt)
    else
      FracPart := '';
    
    // Ограничиваем дробную часть одной цифрой
    if Length(FracPart) > 1 then
      FracPart := Copy(FracPart, 1, 1);
    
    if FracPart <> '' then
      CleanText := IntPart + ',' + FracPart
    else if IntPart <> '' then
      CleanText := IntPart
    else
      CleanText := '';
  end
  else
  begin
    // Нет разделителя - только целая часть
    if Length(IntPart) > 2 then
      IntPart := Copy(IntPart, 1, 2);
    CleanText := IntPart;
  end;
  
  AText := CleanText;
end;

procedure TFormattedEdit.KeyDown(var Key: Word; var KeyChar: Char; Shift: TShiftState);
var
  NewText: string;
  CaretPos: Integer;
begin
  // Разрешаем управляющие клавиши
  case Key of
    vkBack, vkDelete, vkLeft, vkRight, vkHome, vkEnd, vkTab, vkReturn:
      begin
        inherited;
        Exit;
      end;
  end;
  
  // Разрешаем комбинации с Ctrl/Cmd (копирование, вставка, вырезание)
  if (ssCtrl in Shift) or (ssCmd in Shift) then
  begin
    inherited;
    Exit;
  end;
  
  // Проверяем вводимый символ
  if KeyChar <> #0 then
  begin
    // Разрешаем только цифры и запятую/точку
    if not (KeyChar in ['0'..'9', ',', '.']) then
    begin
      KeyChar := #0;
      Key := 0;
      inherited;
      Exit;
    end;
    
    // Заменяем точку на запятую
    if KeyChar = '.' then
      KeyChar := ',';
    
    // Формируем предполагаемый новый текст
    CaretPos := SelStart;
    if SelLength > 0 then
      NewText := Copy(Text, 1, CaretPos) + KeyChar + Copy(Text, CaretPos + SelLength + 1, MaxInt)
    else
      NewText := Copy(Text, 1, CaretPos) + KeyChar + Copy(Text, CaretPos + 1, MaxInt);
    
    // Проверяем формат
    if not IsValidFormat(NewText) then
    begin
      KeyChar := #0;
      Key := 0;
    end;
  end;
  
  inherited;
end;

function TFormattedEdit.IsValidFormat(const AText: string): Boolean;
var
  SepPos: Integer;
  IntPart, FracPart: string;
  i: Integer;
begin
  Result := False;
  
  // Пустая строка допустима
  if AText = '' then
    Exit(True);
  
  // Ищем запятую
  SepPos := Pos(',', AText);
  
  if SepPos = 0 then
  begin
    // Без запятой - только целая часть (максимум 2 цифры)
    if Length(AText) > 2 then
      Exit;
    
    for i := 1 to Length(AText) do
      if not (AText[i] in ['0'..'9']) then
        Exit;
    
    Result := True;
  end
  else
  begin
    IntPart := Copy(AText, 1, SepPos - 1);
    FracPart := Copy(AText, SepPos + 1, MaxInt);
    
    // Целая часть: 1-2 цифры
    if (Length(IntPart) = 0) or (Length(IntPart) > 2) then
      Exit;
    
    for i := 1 to Length(IntPart) do
      if not (IntPart[i] in ['0'..'9']) then
        Exit;
    
    // Дробная часть: максимум 1 цифра
    if Length(FracPart) > 1 then
      Exit;
    
    // Если есть дробная часть, проверяем что это цифра
    if (Length(FracPart) = 1) and not (FracPart[1] in ['0'..'9']) then
      Exit;
    
    // Не допускаем вторую запятую
    if Pos(',', FracPart) > 0 then
      Exit;
    
    Result := True;
  end;
end;

function TFormattedEdit.IsCompleteFormat(const AText: string): Boolean;
var
  SepPos: Integer;
  IntPart, FracPart: string;
begin
  Result := False;
  
  if AText = '' then
    Exit;
  
  SepPos := Pos(',', AText);
  if SepPos = 0 then
    Exit;
  
  IntPart := Copy(AText, 1, SepPos - 1);
  FracPart := Copy(AText, SepPos + 1, MaxInt);
  
  // Целая часть: ровно 2 цифры
  if Length(IntPart) <> 2 then
    Exit;
  
  // Дробная часть: ровно 1 цифра
  if Length(FracPart) <> 1 then
    Exit;
  
  Result := True;
end;

function TFormattedEdit.IsValid: Boolean;
begin
  if not IsCompleteFormat(Text) then
    Exit(False);
  
  // Проверяем диапазон
  var Val := GetNumericValue;
  if (Val < FMinValue) or (Val > FMaxValue) then
    Exit(False);
  
  Result := True;
end;

function TFormattedEdit.GetNumericValue: Double;
begin
  Result := 0.0;
  if (Text <> '') and IsCompleteFormat(Text) then
  begin
    try
      Result := StrToFloat(StringReplace(Text, ',', '.', [rfReplaceAll]));
    except
      Result := 0.0;
    end;
  end;
end;

function TFormattedEdit.TryGetValue(out Value: Double): Boolean;
begin
  Result := False;
  Value := 0.0;
  
  if not IsValid then
    Exit;
  
  Value := GetNumericValue;
  Result := True;
end;

procedure TFormattedEdit.SetMaxValue(const Value: Double);
begin
  FMaxValue := Value;
end;

procedure TFormattedEdit.SetMinValue(const Value: Double);
begin
  FMinValue := Value;
end;

end.
