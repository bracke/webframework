with Ada.Characters.Handling;
with Web.Binding.Paths;
with Web.Binding.Decoders.Base64_Decoders;

package body Web.Binding.Auth is

   use Scheme_Strings;

   package Cred_Bytes is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Token);
   package B64 is new Web.Binding.Decoders.Base64_Decoders (Cred_Bytes);

   function Lower (S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := Ada.Characters.Handling.To_Lower (S (I));
      end loop;
      return R;
   end Lower;

   procedure Trim (Text : String; First, Last : out Integer) is
   begin
      First := Text'First;
      Last := Text'Last;
      while First <= Last and then Text (First) = ' ' loop
         First := First + 1;
      end loop;
      while Last >= First and then Text (Last) = ' ' loop
         Last := Last - 1;
      end loop;
   end Trim;

   function Parse (Header : String) return Credentials is
      Result : Credentials;
      F, L, Space : Integer;
   begin
      Trim (Header, F, L);
      if F > L then
         return Result;  --  empty -> invalid
      end if;

      Space := 0;
      for I in F .. L loop
         if Header (I) = ' ' then
            Space := I;
            exit;
         end if;
      end loop;

      declare
         Scheme_Text : constant String :=
           (if Space = 0 then Header (F .. L) else Header (F .. Space - 1));
         Token_Text  : constant String :=
           (if Space = 0 then "" else Header (Space + 1 .. L));
         TF, TL      : Integer;
      begin
         Result.Raw_Scheme :=
           To_Bounded_String (Scheme_Text, Drop => Ada.Strings.Right);
         if Token_Text'Length > 0 then
            Trim (Token_Text, TF, TL);
            Result.Token := Token_Strings.To_Bounded_String
              (Token_Text (TF .. TL), Drop => Ada.Strings.Right);
         end if;
         declare
            Low : constant String := Lower (Scheme_Text);
         begin
            if Low = "basic" then
               Result.Scheme := Scheme_Basic;
            elsif Low = "bearer" then
               Result.Scheme := Scheme_Bearer;
            elsif Low = "digest" then
               Result.Scheme := Scheme_Digest;
            else
               Result.Scheme := Scheme_Other;
            end if;
         end;
         Result.Valid := True;
      end;
      return Result;
   end Parse;

   function Decode_Basic (C : Credentials) return Basic_Credentials is
      Result : Basic_Credentials;
   begin
      if not C.Valid or else C.Scheme /= Scheme_Basic then
         return Result;
      end if;
      declare
         Decoded : constant B64.Result :=
           B64.Decode (Token_Strings.To_String (C.Token),
                       Web.Binding.Paths.Rooted (Header_Value), Header_Value);
      begin
         if not B64.Results.Succeeded (Decoded) then
            return Result;
         end if;
         declare
            Text  : constant String :=
              Cred_Bytes.To_String (B64.Results.Value_Of (Decoded));
            Colon : Integer := 0;
         begin
            for I in Text'Range loop
               if Text (I) = ':' then
                  Colon := I;
                  exit;
               end if;
            end loop;
            if Colon = 0 then
               return Result;  --  no ':' -> not userid:password
            end if;
            Result.User_Id := Field_Strings.To_Bounded_String
              (Text (Text'First .. Colon - 1), Drop => Ada.Strings.Right);
            Result.Password := Field_Strings.To_Bounded_String
              (Text (Colon + 1 .. Text'Last), Drop => Ada.Strings.Right);
            Result.Valid := True;
         end;
      end;
      return Result;
   end Decode_Basic;

end Web.Binding.Auth;
