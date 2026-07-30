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
      return Natural (F.Data (Offset + 1));
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

      if not Has_Bytes (F, F.Sfnt_Base, 12) then
         return False;
      end if;

      Num_Tables := U16 (F, F.Sfnt_Base + 4);

      if not Has_Bytes (F, F.Sfnt_Base + 12, Num_Tables * 16) then
         return False;
      end if;

      for I in 0 .. Num_Tables - 1 loop
         Record_Off := F.Sfnt_Base + 12 + I * 16;

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
      Code : constant Natural := C;
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

      Code : constant Natural := C;
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

      if Seg_Count = 0 then
         return False;
      end if;

      declare
         Lo : Integer := 0;
         Hi : Integer := Seg_Count - 1;
         I  : Natural;
      begin
         --  endCode[] is sorted ascending (the final segment ends at 0xFFFF), so
         --  binary-search for the first segment whose endCode >= Code instead of
         --  scanning every segment; then confirm Code is within its startCode.
         while Lo < Hi loop
            declare
               Mid : constant Integer := Lo + (Hi - Lo) / 2;
            begin
               if U16 (F, End_Count_Off + Mid * 2) >= Code then
                  Hi := Mid;
               else
                  Lo := Mid + 1;
               end if;
            end;
         end loop;

         I          := Natural (Lo);
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
      end;

      return False;
   end Lookup_Cmap_Format_4;

      function Lookup_Cmap_Format_6
     (F     : Font;
      Table : Natural;
      C     : Codepoint;
      Glyph : out Natural) return Boolean
      is
         Code : constant Natural := C;
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
      Code : constant Natural := C;
   begin
      Glyph := 0;

      if not Has_Bytes (F, Table, 16) then
         return False;
      end if;

      Groups := U32 (F, Table + 12);

      if not Has_Bytes (F, Table + 16, Groups * 12) then
         return False;
      end if;

      if Groups = 0 then
         return False;
      end if;

      declare
         Lo : Integer := 0;
         Hi : Integer := Groups - 1;
      begin
         --  Groups are sorted by startCharCode (ascending, non-overlapping), so
         --  endCharCode is ascending too: binary-search for the first group whose
         --  endCharCode >= Code, then confirm Code is at or above its startCode.
         while Lo < Hi loop
            declare
               Mid : constant Integer := Lo + (Hi - Lo) / 2;
            begin
               if U32 (F, Table + 16 + Mid * 12 + 4) >= Code then
                  Hi := Mid;
               else
                  Lo := Mid + 1;
               end if;
            end;
         end loop;

         Group_Off  := Table + 16 + Natural (Lo) * 12;
         Start_Char := U32 (F, Group_Off);
         End_Char   := U32 (F, Group_Off + 4);
         Start_Gid  := U32 (F, Group_Off + 8);

         if Code >= Start_Char and then Code <= End_Char then
            Glyph := Start_Gid + (Code - Start_Char);
            return Glyph /= 0;
         end if;
      end;

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

   function Lookup_Glyph_By_Index
     (F           : Font;
      Glyph_Index : Natural;
      G           : out Glyph_Info) return Glyph_Lookup_Result
   is
      Bounds : Glyph_Bounds;
   begin
      G := (others => <>);

      if not F.Is_Loaded or else Glyph_Index >= F.Num_Glyphs_V then
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

      G.Is_Empty :=
        Bounds.X_Max <= Bounds.X_Min or else Bounds.Y_Max <= Bounds.Y_Min;
      G.Used_Fallback := False;

      return Glyph_Found;
   end Lookup_Glyph_By_Index;

   function Glyph_Index_Of
     (F           : Font;
      C           : Codepoint;
      Glyph_Index : out Natural)
      return Boolean is
   begin
      Glyph_Index := 0;
      return F.Is_Loaded and then Lookup_Glyph_Index (F, C, Glyph_Index);
   end Glyph_Index_Of;

   function Has_Colour_Bitmaps (F : Font) return Boolean is
   begin
      return (F.Cblc_Table.Found and then F.Cbdt_Table.Found)
        or else F.Sbix_Table.Found;
   end Has_Colour_Bitmaps;

   function Has_Colour_Layers (F : Font) return Boolean is
   begin
      --  Both tables are needed: layers without a palette have no colours, and
      --  the outlines they name have to be rasterizable.
      return F.Colr_Table.Found
        and then F.Cpal_Table.Found
        and then F.Loca_Table.Found
        and then F.Glyf_Table.Found;
   end Has_Colour_Layers;

   --  COLR v0: a header, then baseGlyphRecords sorted by glyph id, each naming a
   --  run of layerRecords. Found by binary search, as the sort invites.
   procedure Find_Colour_Base
     (F           : Font;
      Glyph_Index : Natural;
      Found       : out Boolean;
      First_Layer : out Natural;
      Count       : out Natural);

   procedure Find_Colour_Base
     (F           : Font;
      Glyph_Index : Natural;
      Found       : out Boolean;
      First_Layer : out Natural;
      Count       : out Natural)
   is
      Base : constant Natural := F.Colr_Table.Offset;
      Num_Base    : Natural;
      Base_Offset : Natural;
      Low, High   : Integer;
   begin
      Found := False;
      First_Layer := 0;
      Count := 0;

      if not Has_Colour_Layers (F) or else not Has_Bytes (F, Base, 14) then
         return;
      end if;

      --  Version 0 is the layer model. Version 1 adds gradients and its own
      --  records; its v0 part is still readable, so it is not refused here.
      Num_Base := U16 (F, Base + 2);
      Base_Offset := Base + U32 (F, Base + 4);

      Low := 0;
      High := Num_Base - 1;

      while Low <= High loop
         declare
            Middle : constant Natural := Natural ((Low + High) / 2);
            At_Rec : constant Natural := Base_Offset + Middle * 6;
            Gid    : Natural;
         begin
            exit when not Has_Bytes (F, At_Rec, 6);

            Gid := U16 (F, At_Rec);

            if Gid = Glyph_Index then
               First_Layer := U16 (F, At_Rec + 2);
               Count := U16 (F, At_Rec + 4);
               Found := Count > 0;
               return;
            elsif Gid < Glyph_Index then
               Low := Middle + 1;
            else
               High := Middle - 1;
            end if;
         end;
      end loop;
   end Find_Colour_Base;

   function Colour_Layer_Count
     (F           : Font;
      Glyph_Index : Natural)
      return Natural
   is
      Found : Boolean;
      First : Natural;
      Count : Natural;
   begin
      Find_Colour_Base (F, Glyph_Index, Found, First, Count);
      return (if Found then Count else 0);
   exception
      when others =>
         return 0;
   end Colour_Layer_Count;

   function Colour_Layer_At
     (F           : Font;
      Glyph_Index : Natural;
      Layer       : Natural)
      return Colour_Layer
   is
      Result : Colour_Layer;
      Found  : Boolean;
      First  : Natural;
      Count  : Natural;
   begin
      Find_Colour_Base (F, Glyph_Index, Found, First, Count);

      if not Found or else Layer >= Count then
         return Result;
      end if;

      declare
         Colr        : constant Natural := F.Colr_Table.Offset;
         Layer_Base  : constant Natural := Colr + U32 (F, Colr + 8);
         At_Layer    : constant Natural := Layer_Base + (First + Layer) * 4;
         Palette_Idx : Natural;
      begin
         if not Has_Bytes (F, At_Layer, 4) then
            return Result;
         end if;

         Result.Glyph_Index := U16 (F, At_Layer);
         Palette_Idx := U16 (F, At_Layer + 2);

         --  0xFFFF means "the text colour", which this crate does not know here.
         --  Left at opaque black; a caller wanting its own colour can tint it.
         if Palette_Idx = 16#FFFF# then
            return Result;
         end if;

         declare
            Cpal        : constant Natural := F.Cpal_Table.Offset;
            Num_Entries : Natural;
            Records_Off : Natural;
            At_Colour   : Natural;
         begin
            if not Has_Bytes (F, Cpal, 12) then
               return Result;
            end if;

            Num_Entries := U16 (F, Cpal + 2);
            Records_Off := Cpal + U32 (F, Cpal + 8);

            if Palette_Idx >= Num_Entries then
               return Result;
            end if;

            At_Colour := Records_Off + Palette_Idx * 4;

            if not Has_Bytes (F, At_Colour, 4) then
               return Result;
            end if;

            --  CPAL stores colour records blue first, not red.
            Result.Blue  := Byte_At (F, At_Colour);
            Result.Green := Byte_At (F, At_Colour + 1);
            Result.Red   := Byte_At (F, At_Colour + 2);
            Result.Alpha := Byte_At (F, At_Colour + 3);
         end;
      end;

      return Result;
   exception
      when others =>
         return Colour_Layer'(others => <>);
   end Colour_Layer_At;

   function Colr_Version (F : Font) return Natural is
     (if F.Colr_Table.Found and then Has_Bytes (F, F.Colr_Table.Offset, 2)
      then U16 (F, F.Colr_Table.Offset)
      else 0);

   function Has_Colour_Paints (F : Font) return Boolean is
   begin
      return F.Colr_Table.Found
        and then F.Cpal_Table.Found
        and then F.Loca_Table.Found
        and then F.Glyf_Table.Found
        and then Colr_Version (F) >= 1
        and then Has_Bytes (F, F.Colr_Table.Offset, 34);
   end Has_Colour_Paints;

   --  A 24-bit offset, which is what the paint tables use for their children.
   function U24 (F : Font; Offset : Natural) return Natural is
     (Byte_At (F, Offset) * 16#10000#
      + Byte_At (F, Offset + 1) * 16#100#
      + Byte_At (F, Offset + 2));

   --  F2Dot14: a signed fixed-point fraction, used for scales and stop offsets.
   function F2Dot14 (F : Font; Offset : Natural) return Float is
     (Float (I16 (F, Offset)) / 16384.0);

   --  F16Dot16, used by the affine transform entries.
   function F16Dot16 (F : Font; Offset : Natural) return Float is
      --  Read as two halves rather than through U32: a negative value has its
      --  top bit set, and U32 answers a Natural, which cannot hold that.
      High  : constant Natural := U16 (F, Offset);
      Low   : constant Natural := U16 (F, Offset + 2);
      Whole : constant Float :=
        (if High >= 16#8000# then Float (High) - 65536.0 else Float (High));
   begin
      return Whole + Float (Low) / 65536.0;
   end F16Dot16;

   --  The colour a palette entry holds, with the paint's own alpha folded in.
   procedure Palette_Colour
     (F       : Font;
      Index   : Natural;
      Opacity : Float;
      Red     : out Natural;
      Green   : out Natural;
      Blue    : out Natural;
      Alpha   : out Natural);

   procedure Palette_Colour
     (F       : Font;
      Index   : Natural;
      Opacity : Float;
      Red     : out Natural;
      Green   : out Natural;
      Blue    : out Natural;
      Alpha   : out Natural)
   is
      Cpal        : constant Natural := F.Cpal_Table.Offset;
      Num_Entries : Natural;
      Records_Off : Natural;
      At_Colour   : Natural;
      Scale       : constant Float := Float'Max (0.0, Float'Min (1.0, Opacity));
   begin
      --  Opaque black is the fallback, and also what 0xFFFF (the text colour)
      --  resolves to here: this layer does not know the caller's ink.
      Red := 0;
      Green := 0;
      Blue := 0;
      Alpha := Natural (255.0 * Scale);

      if Index = 16#FFFF# or else not Has_Bytes (F, Cpal, 12) then
         return;
      end if;

      Num_Entries := U16 (F, Cpal + 2);
      Records_Off := Cpal + U32 (F, Cpal + 8);

      if Index >= Num_Entries then
         return;
      end if;

      At_Colour := Records_Off + Index * 4;

      if not Has_Bytes (F, At_Colour, 4) then
         return;
      end if;

      --  CPAL records are blue first.
      Blue  := Byte_At (F, At_Colour);
      Green := Byte_At (F, At_Colour + 1);
      Red   := Byte_At (F, At_Colour + 2);
      Alpha := Natural (Float (Byte_At (F, At_Colour + 3)) * Scale);
   end Palette_Colour;

   --  A ColorLine: an extend mode, then a run of stops.
   --
   --  Only the pad extend is honoured, which is every gradient in the fonts this
   --  was built against; repeat and reflect fall back to pad rather than being
   --  refused, so such a gradient is flat at its ends instead of absent.
   procedure Read_Colour_Line
     (F      : Font;
      Offset : Natural;
      Fill   : in out Paint_Fill);

   procedure Read_Colour_Line
     (F      : Font;
      Offset : Natural;
      Fill   : in out Paint_Fill)
   is
      Count : Natural;
   begin
      Fill.Stop_Count := 0;

      if not Has_Bytes (F, Offset, 3) then
         return;
      end if;

      Count := Natural'Min (U16 (F, Offset + 1), Max_Colour_Stops);

      for Index in 1 .. Count loop
         declare
            At_Stop : constant Natural := Offset + 3 + (Index - 1) * 6;
            Stop    : Colour_Stop;
         begin
            exit when not Has_Bytes (F, At_Stop, 6);

            Stop.Position := F2Dot14 (F, At_Stop);
            Palette_Colour
              (F, U16 (F, At_Stop + 2), F2Dot14 (F, At_Stop + 4),
               Stop.Red, Stop.Green, Stop.Blue, Stop.Alpha);

            Fill.Stops (Index) := Stop;
            Fill.Stop_Count := Index;
         end;
      end loop;
   end Read_Colour_Line;

   --  Where a version 1 base glyph's paint tree starts. The records are sorted
   --  by glyph id, so this is a binary search like the version 0 one.
   procedure Find_Base_Paint
     (F           : Font;
      Glyph_Index : Natural;
      Found       : out Boolean;
      Paint       : out Natural);

   procedure Find_Base_Paint
     (F           : Font;
      Glyph_Index : Natural;
      Found       : out Boolean;
      Paint       : out Natural)
   is
      Colr      : constant Natural := F.Colr_Table.Offset;
      Base_List : Natural;
      Num       : Natural;
      Low, High : Integer;
   begin
      Found := False;
      Paint := 0;

      if not Has_Colour_Paints (F) then
         return;
      end if;

      Base_List := Colr + U32 (F, Colr + 14);

      if not Has_Bytes (F, Base_List, 4) then
         return;
      end if;

      Num := U32 (F, Base_List);
      Low := 0;
      High := Num - 1;

      while Low <= High loop
         declare
            Middle : constant Natural := Natural ((Low + High) / 2);
            At_Rec : constant Natural := Base_List + 4 + Middle * 6;
            Gid    : Natural;
         begin
            exit when not Has_Bytes (F, At_Rec, 6);

            Gid := U16 (F, At_Rec);

            if Gid = Glyph_Index then
               Paint := Base_List + U32 (F, At_Rec + 2);
               Found := Has_Bytes (F, Paint, 1);
               return;
            elsif Gid < Glyph_Index then
               Low := Middle + 1;
            else
               High := Middle - 1;
            end if;
         end;
      end loop;
   end Find_Base_Paint;

   function Has_Paint_Graph
     (F           : Font;
      Glyph_Index : Natural)
      return Boolean
   is
      Found : Boolean;
      Paint : Natural;
   begin
      Find_Base_Paint (F, Glyph_Index, Found, Paint);
      return Found;
   exception
      when others =>
         return False;
   end Has_Paint_Graph;

   Max_Paint_Depth : constant := 24;

   function Colour_Draws_For
     (F           : Font;
      Glyph_Index : Natural;
      Draws       : out Colour_Draw_Array;
      Count       : out Natural)
      return Boolean
   is
      Colr       : constant Natural := F.Colr_Table.Offset;
      Layer_List : Natural;
      Total      : Natural := 0;

      --  Walks the tree, carrying the transform in force and the glyph the
      --  nearest enclosing PaintGlyph named. A fill only becomes a draw when
      --  both are known.
      procedure Walk
        (Paint : Natural;
         XX, XY, YX, YY, DX, DY : Float;
         Glyph : Natural;
         Depth : Natural);

      procedure Emit
        (Glyph : Natural;
         XX, XY, YX, YY, DX, DY : Float;
         Fill  : Paint_Fill) is
      begin
         if Total >= Max_Colour_Draws or else Glyph = 0 then
            return;
         end if;

         Total := Total + 1;
         Draws (Total) :=
           (Glyph_Index => Glyph,
            XX => XX, XY => XY, YX => YX, YY => YY, DX => DX, DY => DY,
            Fill => Fill);
      end Emit;

      procedure Walk
        (Paint : Natural;
         XX, XY, YX, YY, DX, DY : Float;
         Glyph : Natural;
         Depth : Natural)
      is
         Format : Natural;
      begin
         if Depth > Max_Paint_Depth
           or else Total >= Max_Colour_Draws
           or else not Has_Bytes (F, Paint, 1)
         then
            return;
         end if;

         Format := Byte_At (F, Paint);

         case Format is
            when 1 =>
               --  PaintColrLayers: a run of paints in the layer list.
               declare
                  Num   : constant Natural := Byte_At (F, Paint + 1);
                  First : constant Natural := U32 (F, Paint + 2);
               begin
                  for Index in 0 .. Num - 1 loop
                     exit when Total >= Max_Colour_Draws;
                     exit when not Has_Bytes (F, Layer_List + 4 + (First + Index) * 4, 4);
                     Walk (Layer_List + U32 (F, Layer_List + 4 + (First + Index) * 4),
                           XX, XY, YX, YY, DX, DY, Glyph, Depth + 1);
                  end loop;
               end;

            when 2 | 3 =>
               --  PaintSolid, and its variable form read as its default.
               declare
                  Fill : Paint_Fill;
               begin
                  Palette_Colour
                    (F, U16 (F, Paint + 1), F2Dot14 (F, Paint + 3),
                     Fill.Red, Fill.Green, Fill.Blue, Fill.Alpha);
                  Emit (Glyph, XX, XY, YX, YY, DX, DY, Fill);
               end;

            when 4 | 5 =>
               declare
                  Fill : Paint_Fill;
               begin
                  Fill.Kind := Linear_Gradient;
                  Read_Colour_Line (F, Paint + U24 (F, Paint + 1), Fill);
                  Fill.X0 := Float (I16 (F, Paint + 4));
                  Fill.Y0 := Float (I16 (F, Paint + 6));
                  Fill.X1 := Float (I16 (F, Paint + 8));
                  Fill.Y1 := Float (I16 (F, Paint + 10));
                  Fill.X2 := Float (I16 (F, Paint + 12));
                  Fill.Y2 := Float (I16 (F, Paint + 14));
                  Emit (Glyph, XX, XY, YX, YY, DX, DY, Fill);
               end;

            when 6 | 7 =>
               declare
                  Fill : Paint_Fill;
               begin
                  Fill.Kind := Radial_Gradient;
                  Read_Colour_Line (F, Paint + U24 (F, Paint + 1), Fill);
                  Fill.X0 := Float (I16 (F, Paint + 4));
                  Fill.Y0 := Float (I16 (F, Paint + 6));
                  Fill.Radius_0 := Float (U16 (F, Paint + 8));
                  Fill.X1 := Float (I16 (F, Paint + 10));
                  Fill.Y1 := Float (I16 (F, Paint + 12));
                  Fill.Radius_1 := Float (U16 (F, Paint + 14));
                  Emit (Glyph, XX, XY, YX, YY, DX, DY, Fill);
               end;

            when 10 =>
               --  PaintGlyph: names the outline its child paint fills.
               Walk (Paint + U24 (F, Paint + 1),
                     XX, XY, YX, YY, DX, DY, U16 (F, Paint + 4), Depth + 1);

            when 11 =>
               --  PaintColrGlyph: another base glyph's paint, reused.
               declare
                  Other : constant Natural := U16 (F, Paint + 1);
                  Found : Boolean;
                  At_Paint : Natural;
               begin
                  Find_Base_Paint (F, Other, Found, At_Paint);

                  if Found then
                     Walk (At_Paint, XX, XY, YX, YY, DX, DY, Glyph, Depth + 1);
                  end if;
               end;

            when 12 | 13 =>
               --  PaintTransform: an affine, composed with what is in force.
               declare
                  Child : constant Natural := Paint + U24 (F, Paint + 1);
                  At_Aff : constant Natural := Paint + U24 (F, Paint + 4);
                  A : constant Float := F16Dot16 (F, At_Aff);
                  B : constant Float := F16Dot16 (F, At_Aff + 4);
                  C : constant Float := F16Dot16 (F, At_Aff + 8);
                  D : constant Float := F16Dot16 (F, At_Aff + 12);
                  E : constant Float := F16Dot16 (F, At_Aff + 16);
                  G : constant Float := F16Dot16 (F, At_Aff + 20);
               begin
                  Walk (Child,
                        XX * A + XY * B, XX * C + XY * D,
                        YX * A + YY * B, YX * C + YY * D,
                        DX + XX * E + XY * G, DY + YX * E + YY * G,
                        Glyph, Depth + 1);
               end;

            when 14 | 15 =>
               declare
                  Child : constant Natural := Paint + U24 (F, Paint + 1);
                  Tx : constant Float := Float (I16 (F, Paint + 4));
                  Ty : constant Float := Float (I16 (F, Paint + 6));
               begin
                  Walk (Child, XX, XY, YX, YY,
                        DX + XX * Tx + XY * Ty, DY + YX * Tx + YY * Ty,
                        Glyph, Depth + 1);
               end;

            when 16 | 17 =>
               declare
                  Child : constant Natural := Paint + U24 (F, Paint + 1);
                  Sx : constant Float := F2Dot14 (F, Paint + 4);
                  Sy : constant Float := F2Dot14 (F, Paint + 6);
               begin
                  Walk (Child, XX * Sx, XY * Sy, YX * Sx, YY * Sy, DX, DY,
                        Glyph, Depth + 1);
               end;

            when 32 =>
               --  PaintComposite. The blend modes are not implemented; both
               --  sides are drawn in order instead, which for the common
               --  source-over case is exactly right and for the clipping modes
               --  shows too much rather than nothing.
               Walk (Paint + U24 (F, Paint + 5), XX, XY, YX, YY, DX, DY, Glyph, Depth + 1);
               Walk (Paint + U24 (F, Paint + 1), XX, XY, YX, YY, DX, DY, Glyph, Depth + 1);

            when others =>
               --  Sweep gradients and the variable-only formats: not drawn.
               null;
         end case;
      end Walk;

      Found    : Boolean;
      At_Paint : Natural;
   begin
      Draws := [others => <>];
      Count := 0;

      if not Has_Colour_Paints (F) then
         return False;
      end if;

      Layer_List := Colr + U32 (F, Colr + 18);

      Find_Base_Paint (F, Glyph_Index, Found, At_Paint);

      if not Found then
         return False;
      end if;

      Walk (At_Paint, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0, 0);
      Count := Total;
      return Count > 0;
   exception
      when others =>
         Count := 0;
         return False;
   end Colour_Draws_For;

   function Is_Bitmap_Only (F : Font) return Boolean is
   begin
      return Has_Colour_Bitmaps (F)
        and then not (F.Loca_Table.Found and then F.Glyf_Table.Found);
   end Is_Bitmap_Only;

   --  A signed byte read as Ada sees it: CBDT's small metrics store bearings as
   --  int8, and reading them unsigned puts a glyph 256 pixels the wrong way.
   function I8 (F : Font; Offset : Natural) return Integer is
      Raw : constant Natural := Byte_At (F, Offset);
   begin
      return (if Raw >= 128 then Raw - 256 else Raw);
   end I8;

   --  CBLC: pick a strike, find the index subtable covering the glyph, and read
   --  the image's position out of CBDT.
   --
   --  Only what real fonts use is implemented, deliberately: index formats 1 and
   --  3 (a 32- or 16-bit offset array) and image formats 17, 18 and 19 (small
   --  metrics, big metrics, or metrics inherited from the strike). Noto Color
   --  Emoji is index format 1 with image format 17 throughout. Anything else
   --  answers "no bitmap" rather than guessing at bytes.
   function Cbdt_Bitmap_For
     (F           : Font;
      Glyph_Index : Natural;
      Pixel_Size  : Positive)
      return Colour_Bitmap
   is
      Result     : Colour_Bitmap;
      Cblc       : constant Natural := F.Cblc_Table.Offset;
      Num_Sizes  : Natural;
      Best_Strike : Natural := 0;
      Best_Ppem   : Natural := 0;
      Found_Strike : Boolean := False;
   begin
      if not Has_Bytes (F, Cblc, 8) then
         return Result;
      end if;

      Num_Sizes := U32 (F, Cblc + 4);

      --  Choose the smallest strike that is at least the requested size, and the
      --  largest available when they are all smaller: downscaling a bitmap keeps
      --  more of it than magnifying one.
      for Strike in 0 .. Num_Sizes - 1 loop
         declare
            Base : constant Natural := Cblc + 8 + Strike * 48;
         begin
            exit when not Has_Bytes (F, Base, 48);

            declare
               Ppem : constant Natural := Byte_At (F, Base + 44);
            begin
               if Ppem > 0 then
                  if not Found_Strike then
                     Best_Strike := Strike;
                     Best_Ppem := Ppem;
                     Found_Strike := True;
                  elsif Best_Ppem < Pixel_Size then
                     --  Everything so far is too small; anything larger is better.
                     if Ppem > Best_Ppem then
                        Best_Strike := Strike;
                        Best_Ppem := Ppem;
                     end if;
                  elsif Ppem >= Pixel_Size and then Ppem < Best_Ppem then
                     Best_Strike := Strike;
                     Best_Ppem := Ppem;
                  end if;
               end if;
            end;
         end;
      end loop;

      if not Found_Strike then
         return Result;
      end if;

      declare
         Base       : constant Natural := Cblc + 8 + Best_Strike * 48;
         Array_Off  : constant Natural := U32 (F, Base);
         Num_Tables : constant Natural := U32 (F, Base + 8);
      begin
         for Entry_Index in 0 .. Num_Tables - 1 loop
            declare
               Rec : constant Natural := Cblc + Array_Off + Entry_Index * 8;
            begin
               exit when not Has_Bytes (F, Rec, 8);

               declare
                  First_Glyph : constant Natural := U16 (F, Rec);
                  Last_Glyph  : constant Natural := U16 (F, Rec + 2);
                  Sub_Off     : constant Natural := U32 (F, Rec + 4);
               begin
                  --  Strike coverage is sparse: real fonts leave gaps between
                  --  subtables, so a glyph in a gap simply has no bitmap.
                  if Glyph_Index >= First_Glyph and then Glyph_Index <= Last_Glyph then
                     declare
                        Header       : constant Natural := Cblc + Array_Off + Sub_Off;
                        Index_Format : Natural;
                        Image_Format : Natural;
                        Data_Base    : Natural;
                        Slot         : constant Natural := Glyph_Index - First_Glyph;
                        Start_Off    : Natural := 0;
                        End_Off      : Natural := 0;
                     begin
                        exit when not Has_Bytes (F, Header, 8);

                        Index_Format := U16 (F, Header);
                        Image_Format := U16 (F, Header + 2);
                        Data_Base    := F.Cbdt_Table.Offset + U32 (F, Header + 4);

                        if Index_Format = 1 then
                           exit when not Has_Bytes (F, Header + 8 + Slot * 4, 8);
                           Start_Off := U32 (F, Header + 8 + Slot * 4);
                           End_Off   := U32 (F, Header + 8 + (Slot + 1) * 4);
                        elsif Index_Format = 3 then
                           exit when not Has_Bytes (F, Header + 8 + Slot * 2, 4);
                           Start_Off := U16 (F, Header + 8 + Slot * 2);
                           End_Off   := U16 (F, Header + 8 + (Slot + 1) * 2);
                        else
                           exit;
                        end if;

                        if End_Off <= Start_Off then
                           --  An empty slot: this glyph is in range but has no image.
                           exit;
                        end if;

                        declare
                           Glyph_Data : constant Natural := Data_Base + Start_Off;
                        begin
                           if Image_Format = 17 then
                              exit when not Has_Bytes (F, Glyph_Data, 9);
                              Result.Height    := Byte_At (F, Glyph_Data);
                              Result.Width     := Byte_At (F, Glyph_Data + 1);
                              Result.Bearing_X := I8 (F, Glyph_Data + 2);
                              Result.Bearing_Y := I8 (F, Glyph_Data + 3);
                              Result.Advance   := Byte_At (F, Glyph_Data + 4);
                              Result.Data_Length := U32 (F, Glyph_Data + 5);
                              Result.Data_Offset := Glyph_Data + 9;
                           elsif Image_Format = 18 then
                              exit when not Has_Bytes (F, Glyph_Data, 12);
                              Result.Height    := Byte_At (F, Glyph_Data);
                              Result.Width     := Byte_At (F, Glyph_Data + 1);
                              Result.Bearing_X := I8 (F, Glyph_Data + 2);
                              Result.Bearing_Y := I8 (F, Glyph_Data + 3);
                              Result.Advance   := Byte_At (F, Glyph_Data + 4);
                              Result.Data_Length := U32 (F, Glyph_Data + 8);
                              Result.Data_Offset := Glyph_Data + 12;
                           elsif Image_Format = 19 then
                              Result.Data_Length := End_Off - Start_Off;
                              Result.Data_Offset := Glyph_Data;
                           else
                              exit;
                           end if;

                           if Result.Data_Length > 0
                             and then Has_Bytes (F, Result.Data_Offset, Result.Data_Length)
                           then
                              Result.Format := Png_Colour_Image;
                              Result.Ppem := Positive'Max (1, Best_Ppem);
                           else
                              Result.Format := No_Colour_Image;
                           end if;
                        end;

                        exit;
                     end;
                  end if;
               end;
            end;
         end loop;
      end;

      return Result;
   end Cbdt_Bitmap_For;

   --  sbix: strikes of per-glyph images, each prefixed by its origin offset and
   --  a four-character type tag. Only "png " is read; Apple also allows "jpg "
   --  and "tiff", which no emoji font uses.
   function Sbix_Bitmap_For
     (F           : Font;
      Glyph_Index : Natural;
      Pixel_Size  : Positive)
      return Colour_Bitmap
   is
      Result      : Colour_Bitmap;
      Sbix        : constant Natural := F.Sbix_Table.Offset;
      Num_Strikes : Natural;
      Best_Offset : Natural := 0;
      Best_Ppem   : Natural := 0;
      Found       : Boolean := False;
   begin
      if not Has_Bytes (F, Sbix, 8) then
         return Result;
      end if;

      Num_Strikes := U32 (F, Sbix + 4);

      for Strike in 0 .. Num_Strikes - 1 loop
         exit when not Has_Bytes (F, Sbix + 8 + Strike * 4, 4);

         declare
            Strike_Off : constant Natural := Sbix + U32 (F, Sbix + 8 + Strike * 4);
         begin
            exit when not Has_Bytes (F, Strike_Off, 4);

            declare
               Ppem : constant Natural := U16 (F, Strike_Off);
            begin
               if Ppem > 0 then
                  if not Found then
                     Best_Offset := Strike_Off;
                     Best_Ppem := Ppem;
                     Found := True;
                  elsif Best_Ppem < Pixel_Size then
                     if Ppem > Best_Ppem then
                        Best_Offset := Strike_Off;
                        Best_Ppem := Ppem;
                     end if;
                  elsif Ppem >= Pixel_Size and then Ppem < Best_Ppem then
                     Best_Offset := Strike_Off;
                     Best_Ppem := Ppem;
                  end if;
               end if;
            end;
         end;
      end loop;

      if not Found then
         return Result;
      end if;

      declare
         --  glyphDataOffsets is numGlyphs + 1 entries after the 4-byte header.
         Offsets : constant Natural := Best_Offset + 4;
         Start_Off : Natural;
         End_Off   : Natural;
      begin
         if not Has_Bytes (F, Offsets + Glyph_Index * 4, 8) then
            return Result;
         end if;

         Start_Off := U32 (F, Offsets + Glyph_Index * 4);
         End_Off   := U32 (F, Offsets + (Glyph_Index + 1) * 4);

         --  Equal offsets mean this glyph has no image in this strike.
         if End_Off <= Start_Off or else End_Off - Start_Off <= 8 then
            return Result;
         end if;

         declare
            Record_Off : constant Natural := Best_Offset + Start_Off;
         begin
            if not Has_Bytes (F, Record_Off, 8) then
               return Result;
            end if;

            --  graphicType is the 4 bytes after the two origin offsets.
            if Byte_At (F, Record_Off + 4) /= Character'Pos ('p')
              or else Byte_At (F, Record_Off + 5) /= Character'Pos ('n')
              or else Byte_At (F, Record_Off + 6) /= Character'Pos ('g')
              or else Byte_At (F, Record_Off + 7) /= Character'Pos (' ')
            then
               return Result;
            end if;

            Result.Bearing_X := I16 (F, Record_Off);
            Result.Bearing_Y := I16 (F, Record_Off + 2);
            Result.Data_Offset := Record_Off + 8;
            Result.Data_Length := (End_Off - Start_Off) - 8;

            if Has_Bytes (F, Result.Data_Offset, Result.Data_Length) then
               --  sbix keeps no size of its own. A record is an origin, a format
               --  tag, and then the picture -- so unlike CBDT, whose glyph record
               --  states height and width, the only place the dimensions exist is
               --  inside the image. Read them from PNG's IHDR, where they sit as
               --  big-endian words at fixed offsets 16 and 20. That is reading a
               --  header, not decoding an image, which this crate leaves to its
               --  caller.
               if Result.Data_Length >= 24
                 and then Has_Bytes (F, Result.Data_Offset, 24)
               then
                  declare
                     W : constant Natural := U32 (F, Result.Data_Offset + 16);
                     H : constant Natural := U32 (F, Result.Data_Offset + 20);
                  begin
                     --  A dimension in a header is not a promise.
                     if W in 1 .. 16_384 and then H in 1 .. 16_384 then
                        Result.Width := W;
                        Result.Height := H;
                     end if;
                  end;
               end if;

               --  A picture whose size could not be established is no use to a
               --  caller that has to allocate for it, so it is not offered.
               if Result.Width > 0 and then Result.Height > 0 then
                  Result.Format := Png_Colour_Image;
                  Result.Ppem := Positive'Max (1, Best_Ppem);
                  Result.Advance := Result.Width;
               end if;
            end if;
         end;
      end;

      return Result;
   end Sbix_Bitmap_For;

   function Colour_Bitmap_For
     (F           : Font;
      Glyph_Index : Natural;
      Pixel_Size  : Positive)
      return Colour_Bitmap
   is
      Result : Colour_Bitmap;
   begin
      if F.Cblc_Table.Found and then F.Cbdt_Table.Found then
         Result := Cbdt_Bitmap_For (F, Glyph_Index, Pixel_Size);

         if Result.Format /= No_Colour_Image then
            return Result;
         end if;
      end if;

      if F.Sbix_Table.Found then
         return Sbix_Bitmap_For (F, Glyph_Index, Pixel_Size);
      end if;

      return Result;
   exception
      when others =>
         return (Format => No_Colour_Image, others => <>);
   end Colour_Bitmap_For;

   function Parse_Tables (F : in out Font) return Boolean is
      --  Find_Table writes its out parameter before it reads F, so passing a
      --  component of F directly made the actual overlap the writable formal
      --  and left the result dependent on by-copy vs by-reference passing.
      --  Collect into a local and store afterwards.
      Info : Table_Info;
   begin
      if not Find_Table (F, 'h', 'e', 'a', 'd', Info) then
         return False;
      end if;
      F.Head_Table := Info;

      if not Find_Table (F, 'h', 'h', 'e', 'a', Info) then
         return False;
      end if;
      F.Hhea_Table := Info;

      if not Find_Table (F, 'm', 'a', 'x', 'p', Info) then
         return False;
      end if;
      F.Maxp_Table := Info;

      if not Find_Table (F, 'h', 'm', 't', 'x', Info) then
         return False;
      end if;
      F.Hmtx_Table := Info;

      if not Find_Table (F, 'c', 'm', 'a', 'p', Info) then
         return False;
      end if;
      F.Cmap_Table := Info;

      --  Colour bitmap strikes, all optional.
      if Find_Table (F, 'C', 'B', 'L', 'C', Info) then
         F.Cblc_Table := Info;
      end if;

      if Find_Table (F, 'C', 'B', 'D', 'T', Info) then
         F.Cbdt_Table := Info;
      end if;

      if Find_Table (F, 's', 'b', 'i', 'x', Info) then
         F.Sbix_Table := Info;
      end if;

      --  Layered colour glyphs: outlines plus a palette, rather than pictures.
      if Find_Table (F, 'C', 'O', 'L', 'R', Info) then
         F.Colr_Table := Info;
      end if;

      if Find_Table (F, 'C', 'P', 'A', 'L', Info) then
         F.Cpal_Table := Info;
      end if;

      --  Outlines are optional when the font carries colour bitmaps instead.
      --  This used to refuse any font without glyf and loca, which is every
      --  colour emoji font: Noto Color Emoji has neither table, so it could not
      --  be loaded at all, let alone held in a fallback chain. A bitmap-only
      --  font now loads and answers every outline query as empty.
      if Find_Table (F, 'l', 'o', 'c', 'a', Info) then
         F.Loca_Table := Info;
      end if;

      if Find_Table (F, 'g', 'l', 'y', 'f', Info) then
         F.Glyf_Table := Info;
      end if;

      if not (F.Loca_Table.Found and then F.Glyf_Table.Found)
        and then not Has_Colour_Bitmaps (F)
      then
         --  Nothing to draw with: no outlines and no bitmaps either.
         return False;
      end if;

      if F.Head_Table.Length < 54
        or else F.Hhea_Table.Length < 36
        or else F.Maxp_Table.Length < 6
      then
         return False;
      end if;

      --  unitsPerEm comes straight off the wire and Units_Per_Em_V is Positive,
      --  so assigning first turned a malformed font (unitsPerEm = 0) into a
      --  Constraint_Error and left the check below unreachable. Validate first.
      declare
         Units_Per_Em : constant Natural := U16 (F, F.Head_Table.Offset + 18);
      begin
         if Units_Per_Em = 0 then
            return False;
         end if;

         F.Units_Per_Em_V := Units_Per_Em;
      end;

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

      --  In fixed-size chunks, not one array the size of the whole file. That array was
      --  on the stack, so a large font -- a CJK collection is tens of megabytes -- did not
      --  fail to load, it overflowed the stack and took the program with it.
      declare
         Chunk : Stream_Element_Array (1 .. 65_536);
         Into  : Natural := 0;
      begin
         loop
            Read (File => File, Item => Chunk, Last => Last);
            exit when Last < Chunk'First;

            for I in Chunk'First .. Last loop
               Into := Into + 1;
               F.Data (Into) := Interfaces.Unsigned_8 (Chunk (I));
            end loop;

            exit when Last < Chunk'Last;
         end loop;

         Close (File);

         if Into /= Size then
            Reset (F);
            return Load_Failed;
         end if;
      end;

      --  A .ttc collection begins with the tag "ttcf". The real font offset tables are
      --  listed after a 12-byte header, and the first is what we render with -- one face
      --  is all the editor asks of it.
      if Has_Bytes (F, 0, 16)
        and then Character'Val (F.Data (F.Data'First)) = 't'
        and then Character'Val (F.Data (F.Data'First + 1)) = 't'
        and then Character'Val (F.Data (F.Data'First + 2)) = 'c'
        and then Character'Val (F.Data (F.Data'First + 3)) = 'f'
      then
         F.Sfnt_Base := U32 (F, 12);
      end if;

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
