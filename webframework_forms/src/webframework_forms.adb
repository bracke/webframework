with Web.Cookie;

package body Webframework_Forms is

   function To_Bytes (S : String) return Byte_Array is
      R : Byte_Array (1 .. S'Length);
   begin
      for I in S'Range loop
         R (1 + (I - S'First)) := Representation.Byte (Character'Pos (S (I)));
      end loop;
      return R;
   end To_Bytes;

   function To_String (B : Byte_Array) return String is
      R : String (1 .. B'Length);
   begin
      for I in B'Range loop
         R (1 + (I - B'First)) := Character'Val (Integer (B (I)));
      end loop;
      return R;
   end To_String;

   procedure Read_Urlencoded
     (Request        : Web.Request.Request_Type;
      Into           : in out Forms.Submission.Data;
      Status         : out Forms.Urlencoded.Decode_Status;
      Name_Capacity  : Positive := 256;
      Value_Capacity : Positive := 4096;
      Limits         : Forms.Limits.Limits := Forms.Limits.Default_Limits)
   is
      Body_S : constant String := Web.Request.Request_Body (Request);
      D      : Forms.Urlencoded.Decoder (Name_Capacity, Value_Capacity);
   begin
      Forms.Urlencoded.Decode (D, To_Bytes (Body_S), Into, Limits, Status);
   end Read_Urlencoded;

   procedure New_Token (Tok : out Forms.CSRF.Token; Ok : out Boolean) is
   begin
      Forms.CSRF.Generate (Tok, Ok);
   end New_Token;

   function Token_Hex (Tok : Forms.CSRF.Token) return String is
     (Forms.CSRF.To_Hex (Tok));

   function Set_Cookie
     (Tok    : Forms.CSRF.Token;
      Name   : String := Default_Cookie;
      Secure : Boolean := True) return String is
     (Web.Cookie.Set_Cookie
        (Name      => Name,
         Value     => Token_Hex (Tok),
         Path      => "/",
         Http_Only => True,
         Secure    => Secure,
         Same_Site => Web.Cookie.Strict));

   function Verify_Csrf
     (Request : Web.Request.Request_Type;
      Sub     : Forms.Submission.Data;
      Field   : Byte_Array := Forms.CSRF.Default_Field;
      Name    : String := Default_Cookie) return Boolean
   is
      Jar : constant Web.Cookie.Cookie_Jar :=
        Web.Cookie.Parse (Web.Request.Header (Request, "Cookie"));
   begin
      if not Web.Cookie.Has (Jar, Name) then
         return False;
      end if;
      declare
         Expected : Forms.CSRF.Token;
         Ok       : Boolean;
      begin
         Forms.CSRF.Of_Hex (Web.Cookie.Value (Jar, Name), Expected, Ok);
         if not Ok then
            return False;
         end if;
         return Forms.CSRF.Verify_Submission (Sub, Field, Expected);
      end;
   end Verify_Csrf;

end Webframework_Forms;
