with Ada.Strings.Fixed;

package body Web.Binding.Paths is

   use Name_Strings;

   --  Bound a name to Max_Segment_Name characters, recording whether it was cut.
   procedure Make_Name
     (Text      : String;
      Name      : out Segment_Name;
      Truncated : out Boolean) is
   begin
      Truncated := Text'Length > Max_Segment_Name;
      Name := To_Bounded_String (Text, Drop => Ada.Strings.Right);
   end Make_Name;

   --  Append one segment, saturating at Max_Depth.
   function With_Segment
     (Path      : Field_Path;
      Segment   : Path_Segment;
      Truncated : Boolean := False) return Field_Path
   is
      Result : Field_Path := Path;
   begin
      if Result.Length >= Max_Depth then
         Result.Truncated_Flag := True;
         return Result;
      end if;
      Result.Length := Result.Length + 1;
      Result.Segments (Result.Length) := Segment;
      Result.Truncated_Flag := Result.Truncated_Flag or else Truncated;
      return Result;
   end With_Segment;

   function Empty_Path return Field_Path is
      Result : Field_Path;
   begin
      return Result;
   end Empty_Path;

   function Rooted (Root : Source_Kind) return Field_Path is
   begin
      return With_Segment
        (Empty_Path, (Kind => Root_Segment, Root => Root));
   end Rooted;

   function Append_Field (Path : Field_Path; Name : String) return Field_Path is
      Bounded : Segment_Name;
      Cut     : Boolean;
   begin
      Make_Name (Name, Bounded, Cut);
      return With_Segment
        (Path, (Kind => Field_Segment, Name => Bounded), Cut);
   end Append_Field;

   function Append_Index
     (Path : Field_Path; Index : Index_Number) return Field_Path is
   begin
      return With_Segment (Path, (Kind => Index_Segment, Index => Index));
   end Append_Index;

   function Append_Key (Path : Field_Path; Key : String) return Field_Path is
      Bounded : Segment_Name;
      Cut     : Boolean;
   begin
      Make_Name (Key, Bounded, Cut);
      return With_Segment (Path, (Kind => Key_Segment, Name => Bounded), Cut);
   end Append_Key;

   function Append_Alternative
     (Path : Field_Path; Name : String) return Field_Path
   is
      Bounded : Segment_Name;
      Cut     : Boolean;
   begin
      Make_Name (Name, Bounded, Cut);
      return With_Segment
        (Path, (Kind => Alternative_Segment, Name => Bounded), Cut);
   end Append_Alternative;

   function Depth (Path : Field_Path) return Depth_Count is
   begin
      return Depth_Count (Path.Length);
   end Depth;

   function Truncated (Path : Field_Path) return Boolean is
   begin
      return Path.Truncated_Flag;
   end Truncated;

   function Source_Root_Key (Root : Source_Kind) return String is
   begin
      case Root is
         when Route_Parameter   => return "route";
         when Query_Parameter   => return "query";
         when Header_Value      => return "headers";
         when Cookie_Value      => return "cookies";
         when URL_Encoded_Field => return "body";
         when Multipart_Field   => return "multipart";
         when Multipart_Upload  => return "multipart";
         when Structured_Body   => return "body";
      end case;
   end Source_Root_Key;

   function Last_Name (Path : Field_Path) return String is
   begin
      for I in reverse 1 .. Path.Length loop
         if Path.Segments (I).Kind in Field_Segment | Key_Segment then
            return To_String (Path.Segments (I).Name);
         end if;
      end loop;
      return "";
   end Last_Name;

   --  Render an index number without the leading space Ada'Image inserts.
   function Index_Image (Index : Index_Number) return String is
   begin
      return Ada.Strings.Fixed.Trim
        (Index_Number'Image (Index), Ada.Strings.Left);
   end Index_Image;

   function Render (Path : Field_Path) return String is
      --  The rendered length is bounded by depth and per-segment name length,
      --  so a fixed buffer sized to the worst case needs no dynamic growth.
      Buffer : String (1 .. Max_Depth * (Max_Segment_Name + 3) + 16);
      Last   : Natural := 0;

      procedure Put (Text : String) is
      begin
         Buffer (Last + 1 .. Last + Text'Length) := Text;
         Last := Last + Text'Length;
      end Put;

   begin
      for I in 1 .. Path.Length loop
         declare
            Segment : Path_Segment renames Path.Segments (I);
         begin
            case Segment.Kind is
               when Root_Segment =>
                  Put (Source_Root_Key (Segment.Root));
               when Field_Segment | Key_Segment =>
                  Put (".");
                  Put (To_String (Segment.Name));
               when Index_Segment =>
                  Put ("[");
                  Put (Index_Image (Segment.Index));
                  Put ("]");
               when Alternative_Segment =>
                  Put ("<");
                  Put (To_String (Segment.Name));
                  Put (">");
            end case;
         end;
      end loop;
      return Buffer (1 .. Last);
   end Render;

end Web.Binding.Paths;
