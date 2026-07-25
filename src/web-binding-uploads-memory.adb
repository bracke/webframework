package body Web.Binding.Uploads.Memory is

   --  8-hex-digit rendering of the low 32 bits of a rolling checksum.
   function Hex8 (V : Long_Long_Integer) return String is
      Digits_Set : constant String := "0123456789abcdef";
      R : String (1 .. 8);
      X : Long_Long_Integer := V mod (2 ** 32);
   begin
      for I in reverse 1 .. 8 loop
         R (I) := Digits_Set (Integer (X mod 16) + 1);
         X := X / 16;
      end loop;
      return R;
   end Hex8;

   procedure Configure
     (Sink : in out Memory_Sink; Inject : Fault_Kind; Fail_After : Natural := 0)
   is
   begin
      Sink.Inject := Inject;
      Sink.Fail_After := Fail_After;
      Sink.Writes := 0;
   end Configure;

   function Bytes_Of
     (Sink : Memory_Sink; Ref : Natural) return Web.Binding.Byte_Count is
     (Sink.Items (Ref).Bytes);

   function Aborted (Sink : Memory_Sink; Ref : Natural) return Boolean is
     (Sink.Items (Ref).Aborted_F);

   function Finished (Sink : Memory_Sink; Ref : Natural) return Boolean is
     (Sink.Items (Ref).Finished_F);

   overriding procedure Begin_Upload
     (Sink         : in out Memory_Sink;
      Filename     : String;
      Content_Type : String;
      Ref          : out Natural;
      Ok           : out Boolean) is
   begin
      Ref := 0;
      if Sink.Inject = Fail_Begin or else Sink.Used >= Max_Staged then
         Ok := False;
         return;
      end if;
      Sink.Used := Sink.Used + 1;
      Sink.Items (Sink.Used) :=
        (Filename => Meta_Strings.To_Bounded_String
           (Filename, Drop => Ada.Strings.Right),
         Content_Type => Meta_Strings.To_Bounded_String
           (Content_Type, Drop => Ada.Strings.Right),
         Bytes => 0, Sum => 0, Finished_F => False, Aborted_F => False);
      Ref := Sink.Used;
      Ok := True;
   end Begin_Upload;

   overriding procedure Write_Chunk
     (Sink : in out Memory_Sink;
      Ref  : Natural;
      Data : String;
      Ok   : out Boolean) is
   begin
      Sink.Writes := Sink.Writes + 1;
      if Sink.Inject = Fail_Write and then Sink.Writes > Sink.Fail_After then
         Ok := False;
         return;
      end if;
      for C of Data loop
         Sink.Items (Ref).Sum :=
           (Sink.Items (Ref).Sum * 31 + Character'Pos (C)) mod (2 ** 32);
      end loop;
      Sink.Items (Ref).Bytes :=
        Sink.Items (Ref).Bytes + Web.Binding.Byte_Count (Data'Length);
      Ok := True;
   end Write_Chunk;

   overriding procedure Finish_Upload
     (Sink : in out Memory_Sink;
      Ref  : Natural;
      Meta : out Upload_Meta;
      Ok   : out Boolean) is
   begin
      if Sink.Inject = Fail_Finish then
         Ok := False;
         Meta := (others => <>);
         return;
      end if;
      Sink.Items (Ref).Finished_F := True;
      Meta :=
        (Filename => Sink.Items (Ref).Filename,
         Content_Type => Sink.Items (Ref).Content_Type,
         Byte_Count => Sink.Items (Ref).Bytes,
         Checksum => Meta_Strings.To_Bounded_String
           (Hex8 (Sink.Items (Ref).Sum)));
      Ok := True;
   end Finish_Upload;

   overriding procedure Abort_Upload
     (Sink : in out Memory_Sink; Ref : Natural) is
   begin
      Sink.Items (Ref).Aborted_F := True;
   end Abort_Upload;

end Web.Binding.Uploads.Memory;
