unit LDPERollCalculator;

interface

{
  Функция расчета веса рулона LDPE пленки в килограммах
  
  Параметры:
    Width_cm - ширина рулона в сантиметрах
    CoreDiameter_cm - диаметр втулки (картонной гильзы) в сантиметрах
    Edge_cm - торец рулона в сантиметрах (расстояние от края втулки до внешнего края рулона)
    Density_g_cm3 - плотность материала в г/см³ (по умолчанию 0.92 для LDPE)
  
  Возвращает:
    Вес рулона в килограммах
}
function CalculateLDPERollWeight(
  Width_cm: Double;
  CoreDiameter_cm: Double;
  Edge_cm: Double;
  Density_g_cm3: Double = 0.92
): Double;

implementation

uses
  System.Math;

function CalculateLDPERollWeight(
  Width_cm: Double;
  CoreDiameter_cm: Double;
  Edge_cm: Double;
  Density_g_cm3: Double = 0.92
): Double;
var
  OuterDiameter_cm, OuterRadius_cm, CoreRadius_cm: Double;
  Volume_cm3: Double;
  Weight_grams: Double;
begin
  // Проверка входных данных
  if (Width_cm <= 0) or (CoreDiameter_cm <= 0) or (Edge_cm <= 0) then
  begin
    Result := 0;
    Exit;
  end;

  // Расчет внешнего диаметра рулона
  // Торец = (Внешний диаметр - Диаметр втулки) / 2
  // Следовательно: Внешний диаметр = Диаметр втулки + (2 × Торец)
  OuterDiameter_cm := CoreDiameter_cm + (2 * Edge_cm);
  
  // Расчет радиусов
  OuterRadius_cm := OuterDiameter_cm / 2;
  CoreRadius_cm := CoreDiameter_cm / 2;
  
  // Расчет объема пленки (объем цилиндрического кольца)
  // V = π × (R² - r²) × H
  Volume_cm3 := Pi * (Sqr(OuterRadius_cm) - Sqr(CoreRadius_cm)) * Width_cm;
  
  // Расчет веса в граммах (Вес = Объем × Плотность)
  Weight_grams := Volume_cm3 * Density_g_cm3;
  
  // Перевод в килограммы
  Result := Weight_grams / 1000;
end;

end.
