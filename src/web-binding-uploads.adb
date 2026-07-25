package body Web.Binding.Uploads is

   package MP renames Web.Binding.Multipart;

   procedure Configure
     (Session        : in out Upload_Session;
      Max_Per_Upload : Web.Binding.Byte_Count;
      Max_Total      : Web.Binding.Byte_Count) is
   begin
      Session.Max_Per := Max_Per_Upload;
      Session.Max_Total := Max_Total;
   end Configure;

   --  Abort the staged upload in a slot (idempotent).
   procedure Abort_Slot (Session : in out Upload_Session; Slot : Positive) is
   begin
      if Session.Slots (Slot).Active then
         Session.Slots (Slot).Active := False;
         Abort_Upload (Session.Sink.all, Session.Slots (Slot).Ref);
      end if;
   end Abort_Slot;

   procedure Stage
     (Session      : in out Upload_Session;
      Filename     : String;
      Content_Type : String;
      Handle       : out Upload_Handle;
      Status       : out Upload_Status)
   is
      Ref : Natural;
      Ok  : Boolean;
   begin
      Handle := Null_Handle;
      if Session.Used >= Max_Uploads then
         Status := Too_Many_Uploads;
         return;
      end if;
      Begin_Upload (Session.Sink.all, Filename, Content_Type, Ref, Ok);
      if not Ok then
         Status := Sink_Rejected;
         return;
      end if;
      Session.Used := Session.Used + 1;
      Session.Slots (Session.Used) :=
        (Ref => Ref, Bytes => 0, Active => True, Committed => False,
         Meta =>
           (Filename => Meta_Strings.To_Bounded_String
              (Filename, Drop => Ada.Strings.Right),
            Content_Type => Meta_Strings.To_Bounded_String
              (Content_Type, Drop => Ada.Strings.Right),
            Byte_Count => 0,
            Checksum => Meta_Strings.Null_Bounded_String));
      Handle := (Slot => Session.Used);
      Status := Upload_Ok;
   end Stage;

   procedure Write
     (Session : in out Upload_Session;
      Handle  : Upload_Handle;
      Data    : String;
      Status  : out Upload_Status)
   is
      Slot : constant Positive := Handle.Slot;
      Len  : constant Web.Binding.Byte_Count := Web.Binding.Byte_Count (Data'Length);
      Ok   : Boolean;
   begin
      if Session.Slots (Slot).Bytes + Len > Session.Max_Per then
         Abort_Slot (Session, Slot);
         Status := Upload_Too_Large;
         return;
      end if;
      if Session.Total + Len > Session.Max_Total then
         Abort_Slot (Session, Slot);
         Status := Aggregate_Too_Large;
         return;
      end if;
      Write_Chunk (Session.Sink.all, Session.Slots (Slot).Ref, Data, Ok);
      if not Ok then
         Abort_Slot (Session, Slot);
         Status := Sink_Rejected;
         return;
      end if;
      Session.Slots (Slot).Bytes := Session.Slots (Slot).Bytes + Len;
      Session.Total := Session.Total + Len;
      Status := Upload_Ok;
   end Write;

   procedure Complete
     (Session : in out Upload_Session;
      Handle  : Upload_Handle;
      Status  : out Upload_Status)
   is
      Slot : constant Positive := Handle.Slot;
      Meta : Upload_Meta;
      Ok   : Boolean;
   begin
      Finish_Upload (Session.Sink.all, Session.Slots (Slot).Ref, Meta, Ok);
      if not Ok then
         Abort_Slot (Session, Slot);
         Status := Sink_Rejected;
         return;
      end if;
      Session.Slots (Slot).Meta := Meta;
      Status := Upload_Ok;
   end Complete;

   procedure Stream_Part
     (Session : in out Upload_Session;
      Reader  : in out Web.Binding.Multipart.Multipart_Reader;
      Info    : Web.Binding.Multipart.Part_Info;
      Handle  : out Upload_Handle;
      Status  : out Upload_Status)
   is
      Chunk : String (1 .. 4_096);
      Len   : Natural;
      Done  : Boolean;
   begin
      Stage
        (Session,
         MP.Meta_Strings.To_String (Info.Filename),
         MP.Meta_Strings.To_String (Info.Content_Type),
         Handle, Status);
      if Status /= Upload_Ok then
         --  Drain the part so the reader stays aligned.
         MP.Skip_Body (Reader);
         return;
      end if;

      loop
         MP.Read_Body (Reader, Chunk, Len, Done);
         if Len >= Chunk'First then
            Write (Session, Handle, Chunk (Chunk'First .. Len), Status);
            if Status /= Upload_Ok then
               MP.Skip_Body (Reader);
               return;
            end if;
         end if;
         exit when Done;
      end loop;

      Complete (Session, Handle, Status);
   end Stream_Part;

   function Handle_Meta
     (Session : Upload_Session; Handle : Upload_Handle) return Upload_Meta is
   begin
      return Session.Slots (Handle.Slot).Meta;
   end Handle_Meta;

   function Count (Session : Upload_Session) return Natural is
     (Session.Used);

   procedure Commit (Session : in out Upload_Session) is
   begin
      for I in 1 .. Session.Used loop
         if Session.Slots (I).Active then
            Session.Slots (I).Committed := True;
         end if;
      end loop;
   end Commit;

   procedure Discard (Session : in out Upload_Session) is
   begin
      for I in 1 .. Session.Used loop
         if Session.Slots (I).Active and then not Session.Slots (I).Committed then
            Abort_Slot (Session, I);
         end if;
      end loop;
   end Discard;

   overriding procedure Finalize (Session : in out Upload_Session) is
   begin
      Discard (Session);
   end Finalize;

end Web.Binding.Uploads;
