with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Web.Errors;
with Web.Security;

package body Web.Cookie is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   function Trimmed (Value : String) return String is
   begin
      return Trim (Value, Ada.Strings.Both);
   end Trimmed;

   function Is_Token_Character (Ch : Character) return Boolean is
   begin
      return (Ch in 'A' .. 'Z')
        or else (Ch in 'a' .. 'z')
        or else (Ch in '0' .. '9')
        or else Ch = '!'
        or else Ch = '#'
        or else Ch = '$'
        or else Ch = '%'
        or else Ch = '&'
        or else Ch = Character'Val (39)
        or else Ch = '*'
        or else Ch = '+'
        or else Ch = '-'
        or else Ch = '.'
        or else Ch = '^'
        or else Ch = '_'
        or else Ch = '`'
        or else Ch = '|'
        or else Ch = '~';
   end Is_Token_Character;

   function Is_Cookie_Name (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Ch of Value loop
         if not Is_Token_Character (Ch) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Cookie_Name;

   function Is_Cookie_Value (Value : String) return Boolean is
   begin
      for Ch of Value loop
         if Character'Pos (Ch) < 33
           or else Character'Pos (Ch) = 34
           or else Character'Pos (Ch) = 44
           or else Character'Pos (Ch) = 59
           or else Character'Pos (Ch) = 92
           or else Character'Pos (Ch) = 127
           or else (Character'Pos (Ch) >= 128 and then Character'Pos (Ch) <= 159)
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Cookie_Value;

   function Is_Cookie_Path (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      if Value (Value'First) /= '/' then
         return False;
      end if;

      for Ch of Value loop
         if Character'Pos (Ch) < 32
           or else Ch = ';'
           or else Character'Pos (Ch) = 127
           or else (Character'Pos (Ch) >= 128 and then Character'Pos (Ch) <= 159)
         then
            return False;
         end if;
      end loop;

      return Web.Security.Is_Safe_Path (Value)
        and then Web.Security.Is_Safe_Decoded_Path (Value);
   end Is_Cookie_Path;

   procedure Note_Cookie
     (Jar   : in out Cookie_Jar;
      Name  : String;
      Value : String)
   is
      Previous : Natural := 0;
      Count_Position : Cookie_Maps.Cursor := Jar.Counts.Find (Name);
      Value_Position : Cookie_Maps.Cursor;
      Inserted       : Boolean;
   begin
      if Cookie_Maps.Has_Element (Count_Position) then
         Previous := Natural'Value (Cookie_Maps.Element (Count_Position));
      end if;

      if Cookie_Maps.Has_Element (Count_Position) then
         Jar.Counts.Replace_Element (Count_Position, Trimmed (Natural'Image (Previous + 1)));
      else
         Jar.Counts.Insert (Name, Trimmed (Natural'Image (Previous + 1)));
      end if;

      Cookie_Maps.Insert
        (Container => Jar.Values,
         Key       => Name,
         New_Item  => Value,
         Position  => Value_Position,
         Inserted  => Inserted);
   end Note_Cookie;

   function Parse (Header : String) return Cookie_Jar is
      Jar   : Cookie_Jar;
      Start : Positive := Header'First;
      Stop  : Natural;
      Equal : Natural;
   begin
      while Start <= Header'Last loop
         Stop := Start;
         while Stop <= Header'Last and then Header (Stop) /= ';' loop
            Stop := Stop + 1;
         end loop;

         Equal := Index (Header (Start .. Stop - 1), "=");
         if Equal > 0 then
            declare
               Name : constant String := Trimmed (Header (Start .. Equal - 1));
               Item : constant String := Trimmed (Header (Equal + 1 .. Stop - 1));
            begin
               if Is_Cookie_Name (Name)
                 and then Is_Cookie_Value (Item)
               then
                  Note_Cookie (Jar, Name, Item);
               end if;
            end;
         end if;

         Start := Stop + 1;
      end loop;

      return Jar;
   end Parse;

   function Has (Jar : Cookie_Jar; Name : String) return Boolean is
   begin
      if not Is_Cookie_Name (Name) then
         raise Web.Errors.Security_Error with "invalid cookie name";
      end if;

      return Jar.Values.Contains (Name);
   end Has;

   function Value (Jar : Cookie_Jar; Name : String) return String is
      Position : Cookie_Maps.Cursor;
   begin
      if not Is_Cookie_Name (Name) then
         raise Web.Errors.Security_Error with "invalid cookie name";
      end if;

      Position := Jar.Values.Find (Name);
      if Cookie_Maps.Has_Element (Position) then
         return Cookie_Maps.Element (Position);
      end if;

      return "";
   end Value;

   function Count (Jar : Cookie_Jar; Name : String) return Natural is
      Position : Cookie_Maps.Cursor;
   begin
      if not Is_Cookie_Name (Name) then
         raise Web.Errors.Security_Error with "invalid cookie name";
      end if;

      Position := Jar.Counts.Find (Name);
      if Cookie_Maps.Has_Element (Position) then
         return Natural'Value (Cookie_Maps.Element (Position));
      end if;

      return 0;
   end Count;

   function Set_Cookie
     (Name      : String;
      Value     : String;
      Path      : String;
      Http_Only : Boolean := True;
      Secure    : Boolean := False;
      Same_Site : Same_Site_Mode := Lax;
      Max_Age   : Integer := -1) return String
   is
      Result : Unbounded_String := To_Unbounded_String (Name & "=" & Value);
   begin
      if not Is_Cookie_Name (Name) then
         raise Web.Errors.Security_Error with "invalid cookie name";
      end if;

      if not Is_Cookie_Value (Value) then
         raise Web.Errors.Security_Error with "invalid cookie value";
      end if;

      if not Is_Cookie_Path (Path) then
         raise Web.Errors.Security_Error with "invalid cookie path";
      end if;

      if Same_Site = None and then not Secure then
         raise Web.Errors.Security_Error with "SameSite=None cookies must be Secure";
      end if;

      if Max_Age < -1 then
         raise Web.Errors.Security_Error with "invalid cookie max-age";
      end if;

      Append (Result, "; Path=" & Path);

      if Http_Only then
         Append (Result, "; HttpOnly");
      end if;

      if Secure then
         Append (Result, "; Secure");
      end if;

      case Same_Site is
         when Strict =>
            Append (Result, "; SameSite=Strict");
         when Lax =>
            Append (Result, "; SameSite=Lax");
         when None =>
            Append (Result, "; SameSite=None");
      end case;

      if Max_Age >= 0 then
         Append (Result, "; Max-Age=" & Trimmed (Integer'Image (Max_Age)));
      end if;

      return To_String (Result);
   end Set_Cookie;

   function Set_Cookie
     (Name    : String;
      Value   : String;
      Options : Cookie_Options) return String
   is
   begin
      return Set_Cookie
        (Name      => Name,
         Value     => Value,
         Path      => Options.Path,
         Http_Only => Options.Http_Only,
         Secure    => Options.Secure,
         Same_Site => Options.Same_Site,
         Max_Age   => Options.Max_Age);
   end Set_Cookie;
end Web.Cookie;
