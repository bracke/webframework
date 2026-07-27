with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Streams;            use Ada.Streams;

with Web.Cookie;

with Forms.Binding;

with CryptoLib.Hashes;
with CryptoLib.Macs;

package body Webframework_Forms is

   package RD renames Representation.Diagnostics;

   --  Byte_Array / String -> Stream_Element_Array (cryptolib's currency).
   function SE (B : Byte_Array) return Stream_Element_Array is
      R : Stream_Element_Array (1 .. Stream_Element_Offset (B'Length));
   begin
      for I in B'Range loop
         R (Stream_Element_Offset (1 + (I - B'First))) := Stream_Element (B (I));
      end loop;
      return R;
   end SE;

   function SE (S : String) return Stream_Element_Array is
      R : Stream_Element_Array (1 .. Stream_Element_Offset (S'Length));
   begin
      for I in S'Range loop
         R (Stream_Element_Offset (1 + (I - S'First))) :=
           Stream_Element (Character'Pos (S (I)));
      end loop;
      return R;
   end SE;

   function Digest_Bytes (D : CryptoLib.Hashes.SHA256_Digest) return Byte_Array is
      R : Byte_Array (1 .. D'Length);
   begin
      for I in D'Range loop
         R (1 + (I - D'First)) := Representation.Byte (D (I));
      end loop;
      return R;
   end Digest_Bytes;

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

   function Content_Type (Request : Web.Request.Request_Type) return String is
     (Web.Request.Header (Request, "Content-Type"));

   function Is_Urlencoded (Content_Type : String) return Boolean is
     (Ada.Strings.Fixed.Index
        (Content_Type, "application/x-www-form-urlencoded") > 0);

   function Is_Multipart (Content_Type : String) return Boolean is
     (Ada.Strings.Fixed.Index (Content_Type, "multipart/form-data") > 0);

   procedure Read_Body
     (Request : Web.Request.Request_Type;
      Into    : in out Forms.Submission.Data;
      Status  : out Body_Status;
      Limits  : Forms.Limits.Limits := Forms.Limits.Default_Limits)
   is
   begin
      if Is_Urlencoded (Content_Type (Request)) then
         declare
            S : Forms.Urlencoded.Decode_Status;
            use all type Forms.Urlencoded.Decode_Status;
         begin
            Read_Urlencoded (Request, Into, S, Limits => Limits);
            Status :=
              (case S is
                  when Decode_Ok             => Body_Ok,
                  when Decode_Body_Too_Large => Body_Too_Large,
                  when Decode_Capacity       => Body_Capacity,
                  when others                => Body_Malformed);
         end;
      else
         Status := Body_Unsupported_Media;
      end if;
   end Read_Body;

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

   function Session_Token
     (Key : Byte_Array; Session_Id : String) return Forms.CSRF.Token
   is
      D : constant CryptoLib.Hashes.SHA256_Digest :=
        CryptoLib.Macs.HMAC_SHA256
          (Key_Data => SE (Key), Message_Data => SE (Session_Id));
   begin
      return Forms.CSRF.Make (Digest_Bytes (D));
   end Session_Token;

   function Verify_Session_Csrf
     (Sub        : Forms.Submission.Data;
      Key        : Byte_Array;
      Session_Id : String;
      Field      : Byte_Array := Forms.CSRF.Default_Field) return Boolean is
     (Forms.CSRF.Verify_Submission
        (Sub, Field, Session_Token (Key, Session_Id)));

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
