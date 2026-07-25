with Ada.Characters.Handling;

package body Web.Binding.Decoders.URI_Decoders is

   use Web.Binding.Errors;
   use URI_Strings;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.uri"),
         Expected_Type => To_Identifier ("uri"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function TB (S : String) return URI_Strings.Bounded_String is
     (To_Bounded_String (S, Drop => Ada.Strings.Right));

   function Lower (S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := Ada.Characters.Handling.To_Lower (S (I));
      end loop;
      return R;
   end Lower;

   function All_Digits (S : String) return Boolean is
   begin
      if S'Length = 0 then
         return False;
      end if;
      for C of S loop
         if C not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end All_Digits;

   function Valid_Scheme (S : String) return Boolean is
   begin
      if S'Length = 0 or else S (S'First) not in 'a' .. 'z' | 'A' .. 'Z' then
         return False;
      end if;
      for C of S loop
         case C is
            when 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '+' | '-' | '.' =>
               null;
            when others =>
               return False;
         end case;
      end loop;
      return True;
   end Valid_Scheme;

   --  Split an authority into host and port; False on a bad host/port.
   function Parse_Authority
     (Auth : String;
      Host : out URI_Strings.Bounded_String;
      Port : out URI_Strings.Bounded_String) return Boolean
   is
      A_First : Integer := Auth'First;
   begin
      Host := Null_Bounded_String;
      Port := Null_Bounded_String;
      --  Strip userinfo before '@'.
      for I in Auth'Range loop
         if Auth (I) = '@' then
            A_First := I + 1;
         end if;
      end loop;

      declare
         HP : constant String := Auth (A_First .. Auth'Last);
      begin
         if HP'Length = 0 then
            return False;
         end if;
         if HP (HP'First) = '[' then
            --  IPv6 literal: host is "[...]", optional ":port" after.
            declare
               RB : Integer := 0;
            begin
               for I in HP'Range loop
                  if HP (I) = ']' then
                     RB := I;
                     exit;
                  end if;
               end loop;
               if RB = 0 then
                  return False;
               end if;
               Host := TB (HP (HP'First .. RB));
               if RB < HP'Last then
                  if HP (RB + 1) /= ':'
                    or else not All_Digits (HP (RB + 2 .. HP'Last))
                  then
                     return False;
                  end if;
                  Port := TB (HP (RB + 2 .. HP'Last));
               end if;
            end;
         else
            declare
               Colon : Integer := 0;
            begin
               for I in reverse HP'Range loop
                  if HP (I) = ':' then
                     Colon := I;
                     exit;
                  end if;
               end loop;
               if Colon = 0 then
                  Host := TB (Lower (HP));
               else
                  Host := TB (Lower (HP (HP'First .. Colon - 1)));
                  if not All_Digits (HP (Colon + 1 .. HP'Last)) then
                     return False;
                  end if;
                  Port := TB (HP (Colon + 1 .. HP'Last));
               end if;
            end;
         end if;
      end;
      return Length (Host) > 0;
   end Parse_Authority;

   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result
   is
      function Fail (Id : Error_Id) return Result is
        (Results.Make_Failure
           (Single_Error (Make_Error (Id, Path, Source))));

      R     : URI_Parts;
      First : Integer := Text'First;
      Last  : Integer := Text'Last;
   begin
      if Text'Length = 0 then
         return Fail (Decode_Invalid_URI);
      end if;
      if Text'Length > Max_URI then
         return Fail (Decode_Value_Too_Long);
      end if;

      --  Fragment, then query, split from the tail.
      for I in First .. Last loop
         if Text (I) = '#' then
            R.Fragment := TB (Text (I + 1 .. Last));
            Last := I - 1;
            exit;
         end if;
      end loop;
      for I in First .. Last loop
         if Text (I) = '?' then
            R.Query := TB (Text (I + 1 .. Last));
            Last := I - 1;
            exit;
         end if;
      end loop;

      --  Scheme: a ':' before any '/'.
      declare
         Scheme_End : Integer := 0;
      begin
         for I in First .. Last loop
            exit when Text (I) = '/';
            if Text (I) = ':' then
               Scheme_End := I;
               exit;
            end if;
         end loop;
         if Scheme_End /= 0 then
            if not Valid_Scheme (Text (First .. Scheme_End - 1)) then
               return Fail (Decode_Invalid_URI);
            end if;
            R.Scheme := TB (Lower (Text (First .. Scheme_End - 1)));
            First := Scheme_End + 1;
         elsif Settings.Require_Scheme then
            return Fail (Decode_Invalid_URI);
         end if;
      end;

      --  Authority.
      if Last - First + 1 >= 2
        and then Text (First) = '/' and then Text (First + 1) = '/'
      then
         First := First + 2;
         declare
            Auth_End : Integer := Last + 1;
         begin
            for I in First .. Last loop
               if Text (I) = '/' then
                  Auth_End := I;
                  exit;
               end if;
            end loop;
            if not Parse_Authority (Text (First .. Auth_End - 1), R.Host, R.Port)
            then
               return Fail (Decode_Invalid_URI);
            end if;
            R.Has_Authority := True;
            First := Auth_End;
         end;
      elsif Settings.Require_Authority then
         return Fail (Decode_Invalid_URI);
      end if;

      if First <= Last then
         R.Path := TB (Text (First .. Last));
      end if;
      return Results.Make_Success (R);
   end Decode;

end Web.Binding.Decoders.URI_Decoders;
