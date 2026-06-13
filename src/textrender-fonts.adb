with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;

package body Textrender.Fonts is

   procedure Free is new Ada.Unchecked_Deallocation
     (Font_Buffer, Font_Buffer_Access);

   procedure Reset (F : in out Font) is
   begin
      if F.Data /= null then
         Free (F.Data);
         F.Data := null;
      end if;

      F := (others => <>);
   end Reset;

   function Loaded (F : Font) return Boolean is
   begin
      return F.Is_Loaded;
   end Loaded;

   function Units_Per_Em (F : Font) return Positive is
   begin
      return F.Units_Per_Em_V;
   end Units_Per_Em;

      function Num_Glyphs (F : Font) return Natural is
   begin
      return F.Num_Glyphs_V;
   end Num_Glyphs;

   function Ascent (F : Font) return Integer is
   begin
      return F.Ascent_V;
   end Ascent;

   function Descent (F : Font) return Integer is
   begin
      return F.Descent_V;
   end Descent;

   function Line_Gap (F : Font) return Integer is
   begin
      return F.Line_Gap_V;
   end Line_Gap;

   function Font_Size (F : Font) return Natural is
   begin
      if F.Data = null then
         return 0;
      else
         return F.Data'Length;
      end if;
   end Font_Size;

   function Has_Bytes
     (F      : Font;
      Offset : Natural;
      Count  : Natural) return Boolean
   is
   begin
      return F.Data /= null
        and then Offset <= Font_Size (F)
        and then Count <= Font_Size (F) - Offset;
   end Has_Bytes;

   function Byte_At
     (F      : Font;
      Offset : Natural) return Natural
   is
   begin
      return F.Data (Offset + 1);
   end Byte_At;

   function U16
     (F      : Font;
      Offset : Natural) return Natural
   is
   begin
      return Byte_At (F, Offset) * 16#100#
        + Byte_At (F, Offset + 1);
   end U16;

   function I16
     (F      : Font;
      Offset : Natural) return Integer
   is
      V : constant Natural := U16 (F, Offset);
   begin
      if V >= 16#8000# then
         return Integer (V) - 16#10000#;
      else
         return Integer (V);
      end if;
   end I16;

   function U32
     (F      : Font;
      Offset : Natural) return Natural
   is
   begin
      return Byte_At (F, Offset) * 16#1000000#
        + Byte_At (F, Offset + 1) * 16#10000#
        + Byte_At (F, Offset + 2) * 16#100#
        + Byte_At (F, Offset + 3);
   end U32;

   function Tag_Matches
     (F      : Font;
      Offset : Natural;
      A, B, C, D : Character) return Boolean
   is
   begin
      return Character'Val (Byte_At (F, Offset))         = A
        and then Character'Val (Byte_At (F, Offset + 1)) = B
        and then Character'Val (Byte_At (F, Offset + 2)) = C
        and then Character'Val (Byte_At (F, Offset + 3)) = D;
   end Tag_Matches;

   function Bit_Set
     (Value : Natural;
      Mask  : Natural) return Boolean
   is
   begin
      return (Value / Mask) mod 2 = 1;
   end Bit_Set;

   function Find_Table
     (F          : Font;
      A, B, C, D : Character;
      T          : out Table_Info) return Boolean
   is
      Num_Tables   : Natural;
      Record_Off   : Natural;
      Table_Offset : Natural;
      Table_Length : Natural;
   begin
      T := (Found => False, Offset => 0, Length => 0);

      if not Has_Bytes (F, 0, 12) then
         return False;
      end if;

      Num_Tables := U16 (F, 4);

      if not Has_Bytes (F, 12, Num_Tables * 16) then
         return False;
      end if;

      for I in 0 .. Num_Tables - 1 loop
         Record_Off := 12 + I * 16;

         if Tag_Matches (F, Record_Off, A, B, C, D) then
            Table_Offset := U32 (F, Record_Off + 8);
            Table_Length := U32 (F, Record_Off + 12);

            if not Has_Bytes (F, Table_Offset, Table_Length) then
               return False;
            end if;

            T :=
              (Found  => True,
               Offset => Table_Offset,
               Length => Table_Length);

            return True;
         end if;
      end loop;

      return False;
   end Find_Table;

   function Glyph_Offset
     (F           : Font;
      Glyph_Index : Natural) return Natural
   is
   begin
      if F.Index_To_Loc_Format_V = 0 then
         return F.Glyf_Table.Offset
           + U16 (F, F.Loca_Table.Offset + Glyph_Index * 2) * 2;
      else
         return F.Glyf_Table.Offset
           + U32 (F, F.Loca_Table.Offset + Glyph_Index * 4);
      end if;
   end Glyph_Offset;

   function Glyph_Data_Range
     (F           : Font;
      Glyph_Index : Natural;
      First       : out Natural;
      Last        : out Natural) return Boolean
   is
   begin
      First := 0;
      Last  := 0;

      if Glyph_Index >= F.Num_Glyphs_V then
         return False;
      end if;

      First := Glyph_Offset (F, Glyph_Index);
      Last  := Glyph_Offset (F, Glyph_Index + 1);

      return True;
   end Glyph_Data_Range;

   function Metric_Glyph_Index
     (F           : Font;
      Glyph_Index : Natural;
      Depth       : Natural := 0) return Natural
   is
      G0 : Natural;
      G1 : Natural;

      Number_Of_Contours : Integer;

      Off             : Natural;
      Flags           : Natural;
      Component_Glyph : Natural;

      Args_Are_Words  : Boolean;
      More_Components : Boolean;

      Has_Scale    : Boolean;
      Has_XY_Scale : Boolean;
      Has_2x2      : Boolean;
   begin
      if Depth > Max_Composite_Depth then
         return Glyph_Index;
      end if;

      if Glyph_Index >= F.Num_Glyphs_V then
         return Glyph_Index;
      end if;

      G0 := Glyph_Offset (F, Glyph_Index);
      G1 := Glyph_Offset (F, Glyph_Index + 1);

      if G1 <= G0 then
         return Glyph_Index;
      end if;

      if not Has_Bytes (F, G0, 10) then
         return Glyph_Index;
      end if;

      Number_Of_Contours := I16 (F, G0);

      --  Simple glyph: own metrics.
      if Number_Of_Contours >= 0 then
         return Glyph_Index;
      end if;

      --  Composite glyph.
      Off := G0 + 10;

      loop
         if not Has_Bytes (F, Off, 4) then
            return Glyph_Index;
         end if;

         Flags           := U16 (F, Off);
         Component_Glyph := U16 (F, Off + 2);
         Off := Off + 4;

         if Bit_Set (Flags, 16#0200#) then
            return Metric_Glyph_Index
              (F           => F,
               Glyph_Index => Component_Glyph,
               Depth       => Depth + 1);
         end if;

         Args_Are_Words  := Bit_Set (Flags, 16#0001#);
         More_Components := Bit_Set (Flags, 16#0020#);

         Has_Scale    := Bit_Set (Flags, 16#0008#);
         Has_XY_Scale := Bit_Set (Flags, 16#0040#);
         Has_2x2      := Bit_Set (Flags, 16#0080#);

         if Args_Are_Words then
            Off := Off + 4;
         else
            Off := Off + 2;
         end if;

         if Has_Scale then
            Off := Off + 2;
         elsif Has_XY_Scale then
            Off := Off + 4;
         elsif Has_2x2 then
            Off := Off + 8;
         end if;

         exit when not More_Components;
      end loop;

      return Glyph_Index;
   end Metric_Glyph_Index;
   function Read_Glyph_Bounds
     (F           : Font;
      Glyph_Index : Natural;
      B           : out Glyph_Bounds) return Boolean
   is
      G0 : Natural;
      G1 : Natural;
   begin
      B := (others => <>);

      if Glyph_Index >= F.Num_Glyphs_V then
         return False;
      end if;

      G0 := Glyph_Offset (F, Glyph_Index);
      G1 := Glyph_Offset (F, Glyph_Index + 1);

      if G1 < G0 then
         return False;
      elsif G1 = G0 then
         return True;
      end if;

      if G0 < F.Glyf_Table.Offset
        or else G1 > F.Glyf_Table.Offset + F.Glyf_Table.Length
        or else not Has_Bytes (F, G0, 10)
      then
         return False;
      end if;

      B.X_Min := I16 (F, G0 + 2);
      B.Y_Min := I16 (F, G0 + 4);
      B.X_Max := I16 (F, G0 + 6);
      B.Y_Max := I16 (F, G0 + 8);

      return True;
   end Read_Glyph_Bounds;

   function Read_Advance_X
     (F           : Font;
      Glyph_Index : Natural) return Natural
   is
      Metric_Off : Natural;
      Last_Off   : Natural;
   begin
      if Glyph_Index < F.Number_Of_HMetrics_V then
         Metric_Off := F.Hmtx_Table.Offset + Glyph_Index * 4;
         return U16 (F, Metric_Off);
      else
         Last_Off := F.Hmtx_Table.Offset + (F.Number_Of_HMetrics_V - 1) * 4;
         return U16 (F, Last_Off);
      end if;
   end Read_Advance_X;

   function Read_Left_Side_Bearing
     (F           : Font;
      Glyph_Index : Natural) return Integer
   is
      Metric_Off : Natural;
      Lsb_Off    : Natural;
   begin
      if Glyph_Index < F.Number_Of_HMetrics_V then
         Metric_Off := F.Hmtx_Table.Offset + Glyph_Index * 4;
         return I16 (F, Metric_Off + 2);
      else
         Lsb_Off :=
           F.Hmtx_Table.Offset
           + F.Number_Of_HMetrics_V * 4
           + (Glyph_Index - F.Number_Of_HMetrics_V) * 2;

         return I16 (F, Lsb_Off);
      end if;
   end Read_Left_Side_Bearing;

   function Lookup_Cmap_Format_0
     (F     : Font;
      Table : Natural;
      C     : Codepoint;
      Glyph : out Natural) return Boolean
   is
      Code : Natural := C;
   begin
      Glyph := 0;

      if Code > 255 then
         return False;
      end if;

      --  format(2), length(2), language(2), glyphIdArray(256)
      if not Has_Bytes (F, Table, 262) then
         return False;
      end if;

      Glyph := Byte_At (F, Table + 6 + Code);

      return Glyph /= 0;
   end Lookup_Cmap_Format_0;

   function Lookup_Cmap_Format_4
     (F     : Font;
      Table : Natural;
      C     : Codepoint;
      Glyph : out Natural) return Boolean
   is
      Seg_Count       : Natural;
      End_Count_Off   : Natural;
      Start_Count_Off : Natural;
      Id_Delta_Off    : Natural;
      Id_Range_Off    : Natural;

      Code       : Natural := C;
      End_Code   : Natural;
      Start_Code : Natural;
      D          : Integer;
      Range_Off  : Natural;
      Glyph_Off  : Natural;
      G          : Natural;
   begin
      Glyph := 0;

      if Code > 16#FFFF# then
         return False;
      end if;

      if not Has_Bytes (F, Table, 16) then
         return False;
      end if;

      Seg_Count := U16 (F, Table + 6) / 2;

      End_Count_Off   := Table + 14;
      Start_Count_Off := End_Count_Off + Seg_Count * 2 + 2;
      Id_Delta_Off    := Start_Count_Off + Seg_Count * 2;
      Id_Range_Off    := Id_Delta_Off + Seg_Count * 2;

      if not Has_Bytes (F, Id_Range_Off, Seg_Count * 2) then
         return False;
      end if;

      for I in 0 .. Seg_Count - 1 loop
         End_Code   := U16 (F, End_Count_Off + I * 2);
         Start_Code := U16 (F, Start_Count_Off + I * 2);

         if Code >= Start_Code and then Code <= End_Code then
            D         := I16 (F, Id_Delta_Off + I * 2);
            Range_Off := U16 (F, Id_Range_Off + I * 2);

            if Range_Off = 0 then
               G := Natural ((Integer (Code) + D) mod 65536);
            else
               Glyph_Off :=
                 Id_Range_Off
                 + I * 2
                 + Range_Off
                 + (Code - Start_Code) * 2;

               if not Has_Bytes (F, Glyph_Off, 2) then
                  return False;
               end if;

               G := U16 (F, Glyph_Off);

               if G /= 0 then
                  G := Natural ((Integer (G) + D) mod 65536);
               end if;
            end if;

            Glyph := G;
            return G /= 0;
         end if;
      end loop;

      return False;
   end Lookup_Cmap_Format_4;

      function Lookup_Cmap_Format_6
     (F     : Font;
      Table : Natural;
      C     : Codepoint;
      Glyph : out Natural) return Boolean
   is
      Code        : Natural := C;
      First_Code  : Natural;
      Entry_Count : Natural;
      Index       : Natural;
   begin
      Glyph := 0;

      --  format(2), length(2), language(2), firstCode(2), entryCount(2)
      if not Has_Bytes (F, Table, 10) then
         return False;
      end if;

      First_Code  := U16 (F, Table + 6);
      Entry_Count := U16 (F, Table + 8);

      if Code < First_Code
        or else Code >= First_Code + Entry_Count
      then
         return False;
      end if;

      if not Has_Bytes (F, Table + 10, Entry_Count * 2) then
         return False;
      end if;

      Index := Code - First_Code;

      Glyph := U16 (F, Table + 10 + Index * 2);

      return Glyph /= 0;
   end Lookup_Cmap_Format_6;

   function Lookup_Cmap_Format_12
     (F     : Font;
      Table : Natural;
      C     : Codepoint;
      Glyph : out Natural) return Boolean
   is
      Groups     : Natural;
      Group_Off  : Natural;
      Start_Char : Natural;
      End_Char   : Natural;
      Start_Gid  : Natural;
      Code       : Natural := C;
   begin
      Glyph := 0;

      if not Has_Bytes (F, Table, 16) then
         return False;
      end if;

      Groups := U32 (F, Table + 12);

      if not Has_Bytes (F, Table + 16, Groups * 12) then
         return False;
      end if;

      for I in 0 .. Groups - 1 loop
         Group_Off  := Table + 16 + I * 12;
         Start_Char := U32 (F, Group_Off);
         End_Char   := U32 (F, Group_Off + 4);
         Start_Gid  := U32 (F, Group_Off + 8);

         if Code >= Start_Char and then Code <= End_Char then
            Glyph := Start_Gid + (Code - Start_Char);
            return Glyph /= 0;
         end if;
      end loop;

      return False;
   end Lookup_Cmap_Format_12;

   function Lookup_Glyph_Index
     (F     : Font;
      C     : Codepoint;
      Glyph : out Natural) return Boolean
   is
      Num_Subtables : Natural;
      Rec_Off       : Natural;
      Platform_ID   : Natural;
      Encoding_ID   : Natural;
      Sub_Offset    : Natural;
      Subtable      : Natural;
      Format        : Natural;

      Best_0  : Natural := 0;
      Best_4  : Natural := 0;
      Best_6  : Natural := 0;
      Best_12 : Natural := 0;
      Have_0  : Boolean := False;
      Have_4  : Boolean := False;
      Have_6  : Boolean := False;
      Have_12 : Boolean := False;
   begin
      Glyph := 0;

      if not F.Cmap_Table.Found or else not Has_Bytes (F, F.Cmap_Table.Offset, 4) then
         return False;
      end if;

      Num_Subtables := U16 (F, F.Cmap_Table.Offset + 2);

      if not Has_Bytes (F, F.Cmap_Table.Offset + 4, Num_Subtables * 8) then
         return False;
      end if;

      for I in 0 .. Num_Subtables - 1 loop
         Rec_Off     := F.Cmap_Table.Offset + 4 + I * 8;
         Platform_ID := U16 (F, Rec_Off);
         Encoding_ID := U16 (F, Rec_Off + 2);
         Sub_Offset  := U32 (F, Rec_Off + 4);
         Subtable    := F.Cmap_Table.Offset + Sub_Offset;

         if Has_Bytes (F, Subtable, 2) then
            Format := U16 (F, Subtable);

            if Format = 12
              and then
                ((Platform_ID = 3 and then Encoding_ID = 10)
                 or else Platform_ID = 0)
            then
               Best_12 := Subtable;
               Have_12 := True;

            elsif Format = 4
              and then
                ((Platform_ID = 3 and then Encoding_ID = 1)
                 or else Platform_ID = 0)
            then
               Best_4 := Subtable;
               Have_4 := True;

            elsif Format = 6 then
               Best_6 := Subtable;
               Have_6 := True;

            elsif Format = 0 then
               Best_0 := Subtable;
               Have_0 := True;
            end if;
         end if;
      end loop;

      if Have_12 and then Lookup_Cmap_Format_12 (F, Best_12, C, Glyph) then
         return True;
      end if;

      if Have_4 and then Lookup_Cmap_Format_4 (F, Best_4, C, Glyph) then
         return True;
      end if;

      if Have_6 and then Lookup_Cmap_Format_6 (F, Best_6, C, Glyph) then
         return True;
      end if;

      if Have_0 and then Lookup_Cmap_Format_0 (F, Best_0, C, Glyph) then
         return True;
      end if;

      return False;
   end Lookup_Glyph_Index;

   function Has_Glyph
     (F : Font;
      C : Codepoint) return Boolean
   is
      Glyph_Index : Natural;
   begin
      if not F.Is_Loaded then
         return False;
      end if;

      return Lookup_Glyph_Index (F, C, Glyph_Index);
   end Has_Glyph;
   function Lookup_Glyph
     (F : Font;
      C : Codepoint;
      G : out Glyph_Info) return Glyph_Lookup_Result
   is
      Glyph_Index : Natural;
      Bounds      : Glyph_Bounds;
      Result      : Glyph_Lookup_Result := Glyph_Found;
   begin
      G := (others => <>);

      if not F.Is_Loaded then
         return Glyph_Not_Found;
      end if;

      if not Lookup_Glyph_Index (F, C, Glyph_Index) then
         Result := Glyph_Used_Fallback;

         if not Lookup_Glyph_Index (F, 16#FFFD#, Glyph_Index)
           and then not Lookup_Glyph_Index (F, Character'Pos ('?'), Glyph_Index)
         then
            Glyph_Index := 0;
         end if;
      end if;

      if Glyph_Index >= F.Num_Glyphs_V then
         return Glyph_Not_Found;
      end if;

      if not Read_Glyph_Bounds (F, Glyph_Index, Bounds) then
         return Glyph_Not_Found;
      end if;

      declare
         Metrics_Index : constant Natural :=
           Metric_Glyph_Index
             (F           => F,
              Glyph_Index => Glyph_Index);
      begin
         G.Glyph_Index       := Glyph_Index;
         G.Bounds            := Bounds;
         G.Advance_X         := Read_Advance_X (F, Metrics_Index);
         G.Left_Side_Bearing := Read_Left_Side_Bearing (F, Metrics_Index);
      end;
      G.Is_Empty          :=
        Bounds.X_Max <= Bounds.X_Min or else Bounds.Y_Max <= Bounds.Y_Min;
      G.Used_Fallback     := Result = Glyph_Used_Fallback;

      return Result;
   end Lookup_Glyph;

   function Parse_Tables (F : in out Font) return Boolean is
   begin
      if not Find_Table (F, 'h', 'e', 'a', 'd', F.Head_Table) then
         return False;
      end if;

      if not Find_Table (F, 'h', 'h', 'e', 'a', F.Hhea_Table) then
         return False;
      end if;

      if not Find_Table (F, 'm', 'a', 'x', 'p', F.Maxp_Table) then
         return False;
      end if;

      if not Find_Table (F, 'h', 'm', 't', 'x', F.Hmtx_Table) then
         return False;
      end if;

      if not Find_Table (F, 'c', 'm', 'a', 'p', F.Cmap_Table) then
         return False;
      end if;

      if not Find_Table (F, 'l', 'o', 'c', 'a', F.Loca_Table) then
         return False;
      end if;

      if not Find_Table (F, 'g', 'l', 'y', 'f', F.Glyf_Table) then
         return False;
      end if;

      if F.Head_Table.Length < 54
        or else F.Hhea_Table.Length < 36
        or else F.Maxp_Table.Length < 6
      then
         return False;
      end if;

      F.Units_Per_Em_V := U16 (F, F.Head_Table.Offset + 18);

      if F.Units_Per_Em_V = 0 then
         return False;
      end if;

      F.Index_To_Loc_Format_V := I16 (F, F.Head_Table.Offset + 50);

      if F.Index_To_Loc_Format_V /= 0
        and then F.Index_To_Loc_Format_V /= 1
      then
         return False;
      end if;

      F.Ascent_V              := I16 (F, F.Hhea_Table.Offset + 4);
      F.Descent_V             := I16 (F, F.Hhea_Table.Offset + 6);
      F.Line_Gap_V            := I16 (F, F.Hhea_Table.Offset + 8);
      F.Number_Of_HMetrics_V  := U16 (F, F.Hhea_Table.Offset + 34);
      F.Num_Glyphs_V          := U16 (F, F.Maxp_Table.Offset + 4);

      if F.Num_Glyphs_V = 0
        or else F.Number_Of_HMetrics_V = 0
        or else F.Number_Of_HMetrics_V > F.Num_Glyphs_V
      then
         return False;
      end if;

      return True;
   end Parse_Tables;

   function Load
     (F    : in out Font;
      Path : String) return Load_Result
   is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;

      File : File_Type;
      Size : Natural;
      Last : Stream_Element_Offset;
   begin
      if Path'Length = 0 then
         return Invalid_Input;
      end if;

      Reset (F);

      if not Ada.Directories.Exists (Path) then
         return Load_Failed;
      end if;

      Size := Natural (Ada.Directories.Size (Path));

      if Size = 0 then
         return Load_Failed;
      end if;

      F.Data := new Font_Buffer (1 .. Size);

      Open
        (File => File,
         Mode => In_File,
         Name => Path);

      declare
         Buffer : Stream_Element_Array
           (1 .. Stream_Element_Offset (Size));
      begin
         Read
           (File => File,
            Item => Buffer,
            Last => Last);

         Close (File);

         if Natural (Last) /= Size then
            Reset (F);
            return Load_Failed;
         end if;

         for I in Buffer'Range loop
            F.Data (Positive (I)) := Natural (Buffer (I));
         end loop;
      end;

      if not Parse_Tables (F) then
         Reset (F);
         return Load_Failed;
      end if;

      F.Is_Loaded := True;

      return Loaded;

   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;

         Reset (F);
         return Load_Failed;
   end Load;

end Textrender.Fonts;