with Ada.Strings.Fixed;
with Ada.Characters.Handling;

package body Web.Multipart is

   use Ada.Strings.Unbounded;

   CRLF : constant String := ASCII.CR & ASCII.LF;

   function Boundary_Of (Content_Type : String) return String is
      Marker : constant String := "boundary=";
      At_Pos : constant Natural :=
        Ada.Strings.Fixed.Index
          (Ada.Characters.Handling.To_Lower (Content_Type), Marker);
   begin
      if At_Pos = 0 then
         return "";
      end if;
      declare
         Start : Integer := At_Pos + Marker'Length;
         Stop  : Integer;
      begin
         --  Value runs to the next ';' or end; may be quoted.
         if Start <= Content_Type'Last and then Content_Type (Start) = '"' then
            Start := Start + 1;
            Stop  := Start;
            while Stop <= Content_Type'Last
              and then Content_Type (Stop) /= '"'
            loop
               Stop := Stop + 1;
            end loop;
            return Content_Type (Start .. Stop - 1);
         else
            Stop := Start;
            while Stop <= Content_Type'Last
              and then Content_Type (Stop) /= ';'
              and then Content_Type (Stop) /= ' '
            loop
               Stop := Stop + 1;
            end loop;
            return Content_Type (Start .. Stop - 1);
         end if;
      end;
   end Boundary_Of;

   --  Pull a quoted attribute value ('name="..."') out of a header line.
   function Attribute (Header : String; Key : String) return String is
      Marker : constant String := Key & "=""";
      At_Pos : constant Natural := Ada.Strings.Fixed.Index (Header, Marker);
   begin
      if At_Pos = 0 then
         return "";
      end if;
      declare
         Start : constant Positive := At_Pos + Marker'Length;
         Stop  : constant Natural :=
           Ada.Strings.Fixed.Index (Header (Start .. Header'Last), """");
      begin
         return (if Stop = 0 then "" else Header (Start .. Stop - 1));
      end;
   end Attribute;

   procedure Parse_Headers (Section : String; Into : in out Part) is
      From : Integer := Section'First;
      Line_End : Natural;
   begin
      loop
         Line_End := Ada.Strings.Fixed.Index (Section (From .. Section'Last), CRLF);
         declare
            Stop : constant Integer :=
              (if Line_End = 0 then Section'Last else Line_End - 1);
            Line : constant String := Section (From .. Stop);
            Lower : constant String := Ada.Characters.Handling.To_Lower (Line);
         begin
            if Ada.Strings.Fixed.Index (Lower, "content-disposition:") = Lower'First then
               Into.Name     := To_Unbounded_String (Attribute (Line, "name"));
               Into.Filename := To_Unbounded_String (Attribute (Line, "filename"));
            elsif Ada.Strings.Fixed.Index (Lower, "content-type:") = Lower'First then
               declare
                  Colon : constant Natural := Ada.Strings.Fixed.Index (Line, ":");
               begin
                  Into.Content_Type := To_Unbounded_String
                    (Ada.Strings.Fixed.Trim
                       (Line (Colon + 1 .. Line'Last), Ada.Strings.Both));
               end;
            end if;
         end;
         exit when Line_End = 0;
         From := Line_End + CRLF'Length;
         exit when From > Section'Last;
      end loop;
      Into.Kind := (if Length (Into.Filename) > 0 then File_Part else Field_Part);
   end Parse_Headers;

   procedure Parse
     (Body_Text : String;
      Boundary  : String;
      Parts     : out Part_Array;
      Count     : out Natural;
      Status    : out Parse_Status)
   is
      Delim : constant String := "--" & Boundary;
      Pos   : Natural;
   begin
      Count  := 0;
      Status := Malformed;

      if Boundary'Length = 0 then
         Status := No_Boundary;
         return;
      end if;

      Pos := Ada.Strings.Fixed.Index (Body_Text, Delim);
      if Pos = 0 then
         Status := No_Boundary;
         return;
      end if;

      loop
         declare
            After : constant Integer := Pos + Delim'Length;
         begin
            --  Closing delimiter "--boundary--".
            exit when After + 1 <= Body_Text'Last
              and then Body_Text (After .. After + 1) = "--";
            --  A part follows only after CRLF.
            exit when not (After + 1 <= Body_Text'Last
                           and then Body_Text (After .. After + 1) = CRLF);

            declare
               Part_Start : constant Integer := After + CRLF'Length;
               Hdr_End    : constant Natural :=
                 Ada.Strings.Fixed.Index
                   (Body_Text (Part_Start .. Body_Text'Last), CRLF & CRLF);
            begin
               if Hdr_End = 0 or else Hdr_End - Part_Start > Max_Header_Bytes then
                  Status := Malformed;
                  return;
               end if;
               declare
                  Content_Start : constant Integer := Hdr_End + 2 * CRLF'Length;
                  Next_Delim    : constant Natural :=
                    Ada.Strings.Fixed.Index
                      (Body_Text (Content_Start .. Body_Text'Last), CRLF & Delim);
                  This          : Part;
               begin
                  if Next_Delim = 0 then
                     Status := Malformed;
                     return;
                  end if;
                  if Count = Parts'Length or else Count = Max_Parts then
                     Status := Too_Many_Parts;
                     return;
                  end if;
                  Parse_Headers (Body_Text (Part_Start .. Hdr_End - 1), This);
                  This.First := Content_Start;
                  This.Last  := Next_Delim - 1;
                  Count := Count + 1;
                  Parts (Parts'First + Count - 1) := This;
                  Pos := Next_Delim + CRLF'Length;
               end;
            end;
         end;
      end loop;

      Status := Ok;
   end Parse;

end Web.Multipart;
