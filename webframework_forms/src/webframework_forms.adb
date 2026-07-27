with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Web.Cookie;

with Forms.Binding;

package body Webframework_Forms is

   package RD renames Representation.Diagnostics;

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

   function Diagnostics_Text
     (Report : Representation.Diagnostics.Diagnostic_Set) return String
   is
      Out_S : Unbounded_String;
   begin
      for I in 1 .. Natural (RD.Count (Report)) loop
         declare
            Item : constant RD.Diagnostic := RD.Element (Report, I);
            Path : constant String := RD.Path_Render (Item);
            Msg  : constant String := RD.Message (Item);
         begin
            Append (Out_S, RD.Error_Identifier (Item));
            if Path /= "" then
               Append (Out_S, " at " & Path);
            end if;
            if Msg /= "" then
               Append (Out_S, ": " & Msg);
            end if;
            Append (Out_S, Character'Val (10));
         end;
      end loop;
      return To_String (Out_S);
   end Diagnostics_Text;

   function Error_Response
     (Report : Representation.Diagnostics.Diagnostic_Set;
      Status : Positive := 400) return Web.Response.Response_Type is
     (Web.Response.Create
        (Status, Diagnostics_Text (Report), "text/plain; charset=utf-8"));

   function Sticky
     (Def       : Forms.Form.Definition;
      Sub       : Forms.Submission.Data;
      Name      : Byte_Array;
      Max_Bytes : Positive := 4096) return String
   is
      Buf      : Byte_Array (1 .. Max_Bytes);
      Last     : Natural;
      Redacted : Boolean;
   begin
      Forms.Binding.Sticky_Value (Def, Sub, Name, Buf, Last, Redacted);
      if Redacted then
         return "";
      end if;
      return To_String (Buf (1 .. Last));
   end Sticky;

end Webframework_Forms;
