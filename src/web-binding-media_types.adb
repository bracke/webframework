with Ada.Characters.Handling;

package body Web.Binding.Media_Types is

   use Tokens;

   function Is_Token_Char (C : Character) return Boolean is
   begin
      case C is
         when 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
            | '!' | '#' | '$' | '%' | '&' | ''' | '*' | '+' | '-' | '.'
            | '^' | '_' | '`' | '|' | '~' =>
            return True;
         when others =>
            return False;
      end case;
   end Is_Token_Char;

   function Lower (S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := Ada.Characters.Handling.To_Lower (S (I));
      end loop;
      return R;
   end Lower;

   --  Trim ASCII spaces and tabs from both ends.
   procedure Bounds (Text : String; First, Last : out Integer) is
   begin
      First := Text'First;
      Last := Text'Last;
      while First <= Last
        and then (Text (First) = ' ' or else Text (First) = Character'Val (9))
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then (Text (Last) = ' ' or else Text (Last) = Character'Val (9))
      loop
         Last := Last - 1;
      end loop;
   end Bounds;

   function All_Token (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return False;
      end if;
      for C of Text loop
         if not Is_Token_Char (C) then
            return False;
         end if;
      end loop;
      return True;
   end All_Token;

   --  Apply one "name=value" parameter to the result.
   procedure Apply_Param (M : in out Media_Type; Text : String) is
      Eq : Integer := 0;
   begin
      for I in Text'Range loop
         if Text (I) = '=' then
            Eq := I;
            exit;
         end if;
      end loop;
      if Eq = 0 then
         return;  --  a valueless parameter is ignored
      end if;

      declare
         NF, NL, VF, VL : Integer;
      begin
         Bounds (Text (Text'First .. Eq - 1), NF, NL);
         Bounds (Text (Eq + 1 .. Text'Last), VF, VL);
         if NF > NL then
            return;
         end if;
         declare
            Name : constant String := Lower (Text (NF .. NL));
            --  Strip surrounding quotes from a quoted value.
            Quoted : constant Boolean :=
              VF <= VL and then Text (VF) = '"' and then Text (VL) = '"'
              and then VF < VL;
            Val : constant String :=
              (if Quoted then Text (VF + 1 .. VL - 1) else Text (VF .. VL));
         begin
            if Name = "charset" then
               M.Charset := To_Bounded_String (Lower (Val), Drop => Ada.Strings.Right);
            elsif Name = "boundary" then
               M.Boundary :=
                 Boundaries.To_Bounded_String (Val, Drop => Ada.Strings.Right);
            end if;
         end;
      end;
   end Apply_Param;

   function Parse (Text : String) return Media_Type is
      Result : Media_Type;
      First, Last, Semi : Integer;
   begin
      Bounds (Text, First, Last);
      if First > Last then
         return Result;  --  empty -> invalid
      end if;

      --  The media range is up to the first ';'.
      Semi := 0;
      for I in First .. Last loop
         if Text (I) = ';' then
            Semi := I;
            exit;
         end if;
      end loop;

      declare
         Range_Last : constant Integer := (if Semi = 0 then Last else Semi - 1);
         RF, RL     : Integer;
         Slash      : Integer := 0;
      begin
         Bounds (Text (First .. Range_Last), RF, RL);
         for I in RF .. RL loop
            if Text (I) = '/' then
               Slash := I;
               exit;
            end if;
         end loop;
         if Slash = 0 then
            return Result;  --  no '/' -> invalid
         end if;

         declare
            Main_Text : constant String := Text (RF .. Slash - 1);
            Sub_Text  : constant String := Text (Slash + 1 .. RL);
         begin
            if not All_Token (Main_Text) or else not All_Token (Sub_Text) then
               return Result;
            end if;
            Result.Main := To_Bounded_String (Lower (Main_Text), Drop => Ada.Strings.Right);
            Result.Sub := To_Bounded_String (Lower (Sub_Text), Drop => Ada.Strings.Right);
            --  Structured suffix: text after the last '+'.
            for I in reverse Sub_Text'Range loop
               if Sub_Text (I) = '+' then
                  Result.Suffix := To_Bounded_String
                    (Lower (Sub_Text (I + 1 .. Sub_Text'Last)),
                     Drop => Ada.Strings.Right);
                  exit;
               end if;
            end loop;
            Result.Valid := True;
         end;
      end;

      --  Parameters after the first ';'.
      if Semi /= 0 then
         declare
            P : Integer := Semi + 1;
            Start : Integer := Semi + 1;
         begin
            while P <= Last loop
               if Text (P) = ';' then
                  Apply_Param (Result, Text (Start .. P - 1));
                  Start := P + 1;
               end if;
               P := P + 1;
            end loop;
            Apply_Param (Result, Text (Start .. Last));
         end;
      end if;

      return Result;
   end Parse;

   function Is_Valid (M : Media_Type) return Boolean is (M.Valid);

   function Has_Suffix (M : Media_Type) return Boolean is
     (Length (M.Suffix) > 0);

   function Normalized (M : Media_Type) return String is
   begin
      if not M.Valid then
         return "";
      end if;
      return To_String (M.Main) & "/" & To_String (M.Sub);
   end Normalized;

end Web.Binding.Media_Types;
