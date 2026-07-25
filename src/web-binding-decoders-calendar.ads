--  Calendar value model and validators shared by the temporal decoders.
--
--  Pure date/time arithmetic and the strongly range-constrained value records
--  the Date, Time and Date_Time decoders produce. Validation is total and
--  non-raising: a syntactically well-formed but impossible date (2026-02-31) is
--  rejected by Valid_Date, which is what makes it a decoding failure rather than
--  an exception.
package Web.Binding.Decoders.Calendar is

   pragma Preelaborate;

   subtype Year_Number   is Integer range 0 .. 9999;
   subtype Month_Number  is Integer range 1 .. 12;
   subtype Day_Number    is Integer range 1 .. 31;
   subtype Hour_Number   is Integer range 0 .. 23;
   subtype Minute_Number is Integer range 0 .. 59;
   --  Second allows 60 for a leap second, as RFC 3339 permits.
   subtype Second_Number is Integer range 0 .. 60;
   subtype Milli_Number  is Integer range 0 .. 999;

   type Date_Value is record
      Year  : Year_Number := 0;
      Month : Month_Number := 1;
      Day   : Day_Number := 1;
   end record;

   type Time_Value is record
      Hour   : Hour_Number := 0;
      Minute : Minute_Number := 0;
      Second : Second_Number := 0;
      Milli  : Milli_Number := 0;
   end record;

   type Date_Time_Value is record
      Date           : Date_Value;
      Time           : Time_Value;
      Has_Offset     : Boolean := False;
      Offset_Minutes : Integer := 0;
   end record;

   --  Whether Year is a Gregorian leap year.
   --  @param Year The year.
   --  @return True for a leap year.
   function Is_Leap_Year (Year : Integer) return Boolean;

   --  The number of days in a month (0 for an out-of-range month).
   --  @param Year The year (for February).
   --  @param Month The month.
   --  @return The day count, or 0 if Month is out of range.
   function Days_In_Month (Year : Integer; Month : Integer) return Natural;

   --  Whether (Year, Month, Day) is a real calendar date.
   --  @param Year The year.
   --  @param Month The month.
   --  @param Day The day.
   --  @return True when the date exists.
   function Valid_Date (Year : Integer; Month : Integer; Day : Integer)
      return Boolean;

   --  Whether (Hour, Minute, Second) is a valid time of day.
   --  @param Hour The hour.
   --  @param Minute The minute.
   --  @param Second The second (60 permitted for a leap second).
   --  @return True when the time is valid.
   function Valid_Time (Hour : Integer; Minute : Integer; Second : Integer)
      return Boolean;

   --  Parse exactly Count decimal digits of Text starting at First into Value.
   --  Total: returns False on any non-digit or short input without raising.
   --  @param Text The source text.
   --  @param First The 1-based-relative start index (Text'First based).
   --  @param Count The exact number of digits to read.
   --  @param Value The parsed value on success.
   --  @return True when Count digits were read.
   function Digits_Value
     (Text  : String;
      First : Integer;
      Count : Integer;
      Value : out Integer) return Boolean;

end Web.Binding.Decoders.Calendar;
