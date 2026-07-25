with Ada.Strings.Bounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Results;
with Web.Binding.Record_Binders;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Decoders.Text_Decoders;
with Web.Binding.Decoders.URI_Decoders;
with Web.Binding.Streams.Memory;
with Web.Binding.Multipart;
with Web.Binding.Multipart.Binding;
with Web.Binding.Uploads;
with Web.Binding.Uploads.Memory;

package body Web_Binding_Extra_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;

   package URI renames Web.Binding.Decoders.URI_Decoders;
   package MP renames Web.Binding.Multipart;
   package MB renames Web.Binding.Multipart.Binding;
   package Mem renames Web.Binding.Streams.Memory;
   package UP renames Web.Binding.Uploads;
   package USink_Pkg renames Web.Binding.Uploads.Memory;
   use type UP.Upload_Status;

   package B32 is new Ada.Strings.Bounded.Generic_Bounded_Length (32);

   --  Target record for the multipart form.
   type Form_Rec is record
      Username : B32.Bounded_String;
      Age      : Integer := 0;
      Avatar   : UP.Upload_Handle;
   end record;

   procedure Set_Username (Rec : in out Form_Rec; Value : B32.Bounded_String) is
   begin
      Rec.Username := Value;
   end Set_Username;

   procedure Set_Age (Rec : in out Form_Rec; Value : Integer) is
   begin
      Rec.Age := Value;
   end Set_Age;

   procedure Set_Avatar (Rec : in out Form_Rec; Value : UP.Upload_Handle) is
   begin
      Rec.Avatar := Value;
   end Set_Avatar;

   package RB is new Web.Binding.Record_Binders (Form_Rec);
   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);
   package Txt is new Web.Binding.Decoders.Text_Decoders (B32);
   package Handle_Results is new Web.Binding.Results (UP.Upload_Handle);

   function Int_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Int_Dec.Results.Result is (Int_Dec.Decode (Text, P, S));
   function Txt_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Txt.Results.Result is (Txt.Decode (Text, P, S));

   function Read_Text_F is new MB.Read_Field
     (B32.Bounded_String, Txt.Results, Txt_Decode);
   function Read_Int_F is new MB.Read_Field
     (Integer, Int_Dec.Results, Int_Decode);

   procedure Assign_Username is new RB.Assign
     (B32.Bounded_String, Txt.Results, Set_Username);
   procedure Assign_Age is new RB.Assign
     (Integer, Int_Dec.Results, Set_Age);
   procedure Assign_Avatar is new RB.Assign
     (UP.Upload_Handle, Handle_Results, Set_Avatar);

   U_Path : constant Field_Path := Append_Field (Rooted (Multipart_Field), "username");
   A_Path : constant Field_Path := Append_Field (Rooted (Multipart_Field), "age");

   NL : constant String := [Character'Val (13), Character'Val (10)];
   Form_Body : constant String :=
     "--BND" & NL
     & "Content-Disposition: form-data; name=""username""" & NL & NL
     & "alice" & NL
     & "--BND" & NL
     & "Content-Disposition: form-data; name=""age""" & NL & NL
     & "30" & NL
     & "--BND" & NL
     & "Content-Disposition: form-data; name=""avatar""; filename=""a.png""" & NL
     & "Content-Type: image/png" & NL & NL
     & "PNGDATA" & NL
     & "--BND--" & NL;

   Default_Form : constant Form_Rec :=
     (Username => B32.Null_Bounded_String, Age => 0, Avatar => UP.Null_Handle);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("extra uri", Test_URI'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("extra multipart bind", Test_Multipart_Bind'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("extra field tracker", Test_Field_Tracker'Access));
   end Add_Tests;

   procedure Test_URI (Item : in out Fixture) is
      pragma Unreferenced (Item);
      P : constant Field_Path := Rooted (Query_Parameter);
      Full : constant URI.Result :=
        URI.Decode ("https://Example.COM:8443/a/b?q=1#frag", P, Query_Parameter);
      Rel  : URI.Config := URI.Default_Config;
   begin
      Assert (URI.Results.Succeeded (Full), "full uri decodes");
      declare
         V : constant URI.URI_Parts := URI.Results.Value_Of (Full);
      begin
         Assert (URI.URI_Strings.To_String (V.Scheme) = "https", "scheme");
         Assert (V.Has_Authority
                   and then URI.URI_Strings.To_String (V.Host) = "example.com"
                   and then URI.URI_Strings.To_String (V.Port) = "8443",
                 "host and port lowercased/split");
         Assert (URI.URI_Strings.To_String (V.Path) = "/a/b", "path");
         Assert (URI.URI_Strings.To_String (V.Query) = "q=1", "query");
         Assert (URI.URI_Strings.To_String (V.Fragment) = "frag", "fragment");
      end;
      --  Invalid forms.
      Assert (not URI.Results.Succeeded (URI.Decode ("//h/x", P, Query_Parameter)),
              "missing required scheme");
      Assert (not URI.Results.Succeeded
                (URI.Decode ("http://h:xx/", P, Query_Parameter)),
              "non-digit port");
      Assert (not URI.Results.Succeeded
                (URI.Decode ("http:///path", P, Query_Parameter)),
              "empty host with authority");
      --  A relative reference when a scheme is not required.
      Rel.Require_Scheme := False;
      Assert (URI.Results.Succeeded (URI.Decode ("/just/a/path", P, Query_Parameter, Rel)),
              "relative path accepted when scheme optional");
   end Test_URI;

   procedure Test_Multipart_Bind (Item : in out Fixture) is
      pragma Unreferenced (Item);
      USink : aliased USink_Pkg.Memory_Sink;
      S       : aliased Mem.Memory_Stream := Mem.Create (Form_Body);
      R       : MP.Multipart_Reader (S'Access);
      Session : UP.Upload_Session (USink'Access);
      B       : RB.Builder := RB.Start (Default_Form);
      Tracker : MB.Field_Tracker := MB.New_Tracker;
      Info  : MP.Part_Info;
      Avail : Boolean;
      Dup   : Boolean;
      H     : UP.Upload_Handle;
      St    : UP.Upload_Status;
      Av_Bytes : Byte_Count := 0;
      Result : RB.Results.Result;
   begin
      MP.Start (R, "BND");
      loop
         MP.Next_Part (R, Info, Avail);
         exit when not Avail;
         declare
            Name : constant String := MP.Meta_Strings.To_String (Info.Name);
         begin
            MB.Note (Tracker, Name, Dup);
            if Name = "username" then
               Assign_Username (B, Read_Text_F (R, U_Path));
            elsif Name = "age" then
               Assign_Age (B, Read_Int_F (R, A_Path));
            elsif Name = "avatar" then
               UP.Stream_Part (Session, R, Info, H, St);
               if St = UP.Upload_Ok then
                  Assign_Avatar (B, Handle_Results.Make_Success (H));
                  Av_Bytes := UP.Handle_Meta (Session, H).Byte_Count;
               end if;
            else
               MP.Skip_Body (R);
            end if;
         end;
      end loop;
      Result := RB.Finish (B);
      UP.Commit (Session);

      Assert (RB.Results.Succeeded (Result), "multipart form binds");
      declare
         V : constant Form_Rec := RB.Results.Value_Of (Result);
      begin
         Assert (B32.To_String (V.Username) = "alice", "text field bound");
         Assert (V.Age = 30, "integer field bound");
      end;
      Assert (Av_Bytes = 7, "file part streamed (7 bytes)");
      Assert (MB.Seen (Tracker, "age") and then MB.Seen (Tracker, "avatar"),
              "tracker saw all fields");
   end Test_Multipart_Bind;

   procedure Test_Field_Tracker (Item : in out Fixture) is
      pragma Unreferenced (Item);
      T   : MB.Field_Tracker := MB.New_Tracker;
      Dup : Boolean;
   begin
      MB.Note (T, "a", Dup);
      Assert (not Dup, "first is new");
      MB.Note (T, "b", Dup);
      Assert (not Dup, "second is new");
      MB.Note (T, "a", Dup);
      Assert (Dup, "repeat detected");
      Assert (MB.Seen (T, "b") and then not MB.Seen (T, "c"), "seen check");
   end Test_Field_Tracker;

end Web_Binding_Extra_Tests;
