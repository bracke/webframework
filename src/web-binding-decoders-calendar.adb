package body Web.Binding.Decoders.Calendar is

   function Is_Leap_Year (Year : Integer) return Boolean is
   begin
      return (Year mod 4 = 0 and then Year mod 100 /= 0)
        or else Year mod 400 = 0;
   end Is_Leap_Year;

   function Days_In_Month (Year : Integer; Month : Integer) return Natural is
   begin
      case Month is
         when 1 | 3 | 5 | 7 | 8 | 10 | 12 => return 31;
         when 4 | 6 | 9 | 11              => return 30;
         when 2 => return (if Is_Leap_Year (Year) then 29 else 28);
         when others => return 0;
      end case;
   end Days_In_Month;

   function Valid_Date (Year : Integer; Month : Integer; Day : Integer)
      return Boolean is
   begin
      return Year in Year_Number
        and then Month in Month_Number
        and then Day >= 1
        and then Day <= Days_In_Month (Year, Month);
   end Valid_Date;

   function Valid_Time (Hour : Integer; Minute : Integer; Second : Integer)
      return Boolean is
   begin
      return Hour in Hour_Number
        and then Minute in Minute_Number
        and then Second in Second_Number;
   end Valid_Time;

   function Digits_Value
     (Text  : String;
      First : Integer;
      Count : Integer;
      Value : out Integer) return Boolean
   is
      Acc : Integer := 0;
   begin
      Value := 0;
      if Count <= 0 or else First < Text'First
        or else First + Count - 1 > Text'Last
      then
         return False;
      end if;
      for Offset in 0 .. Count - 1 loop
         declare
            C : constant Character := Text (First + Offset);
         begin
            if C not in '0' .. '9' then
               return False;
            end if;
            Acc := Acc * 10 + (Character'Pos (C) - Character'Pos ('0'));
         end;
      end loop;
      Value := Acc;
      return True;
   end Digits_Value;

end Web.Binding.Decoders.Calendar;
