with Ada.Containers; use Ada.Containers;
with Ada.Containers.Vectors;

package body Textrender.Rasterizer is

   type Glyph_Point is record
      X        : Float;
      Y        : Float;
      On_Curve : Boolean;
   end record;

   type Segment is record
      X0 : Float;
      Y0 : Float;
      X1 : Float;
      Y1 : Float;
   end record;

   Initial_Contour_Capacity : constant Ada.Containers.Count_Type := 256;
   Initial_Point_Capacity   : constant Ada.Containers.Count_Type := 4096;
   Initial_Segment_Capacity : constant Ada.Containers.Count_Type := 32768;

   package Natural_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Natural);

   package Integer_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Integer);

   package Glyph_Point_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Glyph_Point);

   package Segment_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Segment);

   --  An edge a subsample row crosses, with what its winding test at a point
   --  of that row needs worked out once for the row: the test's cross product
   --  (X1 - X0) * (PY - Y0) - (PX - X0) * (Y1 - Y0) has its first term and
   --  its last factor fixed by the row, and the edge's direction too.
   type Active_Edge is record
      Fixed_Term : Float;
      X0         : Float;
      Rise       : Float;
      Upward     : Boolean;
   end record;

   package Active_Edge_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Active_Edge);

   End_Points_Buffer    : Natural_Vectors.Vector;
   Flags_Buffer         : Natural_Vectors.Vector;
   Xs_Buffer            : Integer_Vectors.Vector;
   Ys_Buffer            : Integer_Vectors.Vector;
   Points_Buffer        : Glyph_Point_Vectors.Vector;
   Segments_Buffer      : Segment_Vectors.Vector;
   Active_Segments_Buffer : Active_Edge_Vectors.Vector;
   Open_Segments_Buffer : Segment_Vectors.Vector;

   --  Whether segment A's top lies above segment B's: the order a glyph's
   --  segments are swept in, from the top row down.
   function Higher (A, B : Segment) return Boolean is
     (Float'Max (A.Y0, A.Y1) > Float'Max (B.Y0, B.Y1));

   package Top_Down is new Segment_Vectors.Generic_Sorting ("<" => Higher);

      procedure Prepare_Buffers is
      begin
         End_Points_Buffer.Clear;
         Flags_Buffer.Clear;
         Xs_Buffer.Clear;
         Ys_Buffer.Clear;
         Points_Buffer.Clear;
         Segments_Buffer.Clear;
         Active_Segments_Buffer.Clear;
         Open_Segments_Buffer.Clear;

         if End_Points_Buffer.Capacity < Initial_Contour_Capacity then
            End_Points_Buffer.Reserve_Capacity (Initial_Contour_Capacity);
         end if;

         if Flags_Buffer.Capacity < Initial_Point_Capacity then
            Flags_Buffer.Reserve_Capacity (Initial_Point_Capacity);
         end if;

         if Xs_Buffer.Capacity < Initial_Point_Capacity then
            Xs_Buffer.Reserve_Capacity (Initial_Point_Capacity);
         end if;

         if Ys_Buffer.Capacity < Initial_Point_Capacity then
            Ys_Buffer.Reserve_Capacity (Initial_Point_Capacity);
         end if;

         if Points_Buffer.Capacity < Initial_Point_Capacity then
            Points_Buffer.Reserve_Capacity (Initial_Point_Capacity);
         end if;

         if Segments_Buffer.Capacity < Initial_Segment_Capacity then
            Segments_Buffer.Reserve_Capacity (Initial_Segment_Capacity);
         end if;

         if Active_Segments_Buffer.Capacity < Initial_Segment_Capacity then
            Active_Segments_Buffer.Reserve_Capacity (Initial_Segment_Capacity);
         end if;
      end Prepare_Buffers;

   function Bit_Set
     (Value : Natural;
      Mask  : Natural) return Boolean
   is
   begin
      return (Value / Mask) mod 2 = 1;
   end Bit_Set;

   function Apply
     (T : Glyph_Transform;
      X : Float;
      Y : Float) return Glyph_Point
   is
   begin
      return
        (X        => T.XX * X + T.XY * Y + T.DX,
         Y        => T.YX * X + T.YY * Y + T.DY,
         On_Curve => True);
   end Apply;

   procedure Add_Segment
     (Segments : in out Segment_Vectors.Vector;
      X0       : Float;
      Y0       : Float;
      X1       : Float;
      Y1       : Float)
   is
   begin
      Segments.Append
        (Segment'(X0 => X0,
          Y0 => Y0,
          X1 => X1,
          Y1 => Y1));
   end Add_Segment;

      procedure Add_Quadratic
     (Segments : in out Segment_Vectors.Vector;
      X0       : Float;
      Y0       : Float;
      CX       : Float;
      CY       : Float;
      X1       : Float;
      Y1       : Float)
      is
         Steps : constant Positive := 8;

         Prev_X : Float := X0;
         Prev_Y : Float := Y0;

         T  : Float;
         MT : Float;
         NX : Float;
         NY : Float;
      begin
         for I in 1 .. Steps loop
            T  := Float (I) / Float (Steps);
            MT := 1.0 - T;

            NX := MT * MT * X0 + 2.0 * MT * T * CX + T * T * X1;
            NY := MT * MT * Y0 + 2.0 * MT * T * CY + T * T * Y1;

            Add_Segment
              (Segments => Segments,
               X0       => Prev_X,
               Y0       => Prev_Y,
               X1       => NX,
               Y1       => NY);

            Prev_X := NX;
            Prev_Y := NY;
         end loop;
      end Add_Quadratic;

   function Rasterize_Simple_Glyph
     (F           : Textrender.Fonts.Font;
      A           : in out Textrender.Atlases.Atlas;
      Glyph_Index : Natural;
      Atlas_X     : Natural;
      Atlas_Y     : Natural;
      Glyph_W     : Positive;
      Glyph_H     : Positive;
      X_Min       : Integer;
      Y_Min       : Integer;
      X_Max       : Integer;
      Y_Max       : Integer;
      Pixel_Size  : Positive;
      Transform   : Glyph_Transform) return Boolean
   is
      --  Y_Min and X_Max belong to the glyph-box signature these callers pass;
      --  only the X_Min/Y_Max corner is needed here.
      pragma Unreferenced (Y_Min, X_Max);
      G0 : Natural;
      G1 : Natural;

      Number_Of_Contours : Integer;

      End_Points     : Natural_Vectors.Vector renames End_Points_Buffer;
      Flags          : Natural_Vectors.Vector renames Flags_Buffer;
      Xs             : Integer_Vectors.Vector renames Xs_Buffer;
      Ys             : Integer_Vectors.Vector renames Ys_Buffer;
      Points         : Glyph_Point_Vectors.Vector renames Points_Buffer;
      Segments       : Segment_Vectors.Vector renames Segments_Buffer;
      Active_Segments : Active_Edge_Vectors.Vector renames Active_Segments_Buffer;
      Open_Segments   : Segment_Vectors.Vector renames Open_Segments_Buffer;
      --  The first segment, top down, the sweep has not yet opened.
      Next_Segment    : Natural := 0;

      End_Points_Off : Natural;
      Instr_Len_Off  : Natural;
      Instr_Len      : Natural;
      P              : Natural;
      Off            : Natural;

      Flag_Value : Natural;
      Repeat_N   : Natural;

      DX : Integer;
      DY : Integer;

      X : Integer := 0;
      Y : Integer := 0;

      Point_Count   : Natural := 0;
      Contour_Count : Natural := 0;

      Scale : constant Float :=
        Float (Pixel_Size) / Float (Textrender.Fonts.Units_Per_Em (F));

      function Midpoint
        (A : Glyph_Point;
         B : Glyph_Point) return Glyph_Point
      is
      begin
         return
           (X        => (A.X + B.X) * 0.5,
            Y        => (A.Y + B.Y) * 0.5,
            On_Curve => True);
      end Midpoint;

      procedure Build_Contour
        (First : Natural;
         Last  : Natural)
      is
         Start_Point : Glyph_Point;
         Current     : Glyph_Point;
         Next        : Glyph_Point;
         After       : Glyph_Point;

         I : Natural;
      begin
         if Points (First).On_Curve then
            Start_Point := Points (First);
            Current     := Points (First);
            I := First + 1;
         else
            if Points (Last).On_Curve then
               Start_Point := Points (Last);
               Current     := Points (Last);
            else
               Start_Point := Midpoint (Points (Last), Points (First));
               Current     := Start_Point;
            end if;

            I := First;
         end if;

         while I <= Last loop
            Next := Points (I);

            if Next.On_Curve then
               Add_Segment
                 (Segments => Segments,
                  X0       => Current.X,
                  Y0       => Current.Y,
                  X1       => Next.X,
                  Y1       => Next.Y);

               Current := Next;
               I := I + 1;

            else
               if I = Last then
                  After := Start_Point;
               else
                  After := Points (I + 1);
               end if;

               if After.On_Curve then
                  Add_Quadratic
                    (Segments => Segments,
                     X0       => Current.X,
                     Y0       => Current.Y,
                     CX       => Next.X,
                     CY       => Next.Y,
                     X1       => After.X,
                     Y1       => After.Y);

                  Current := After;

                  if I = Last then
                     I := Last + 1;
                  else
                     I := I + 2;
                  end if;

               else
                  declare
                     Implied : constant Glyph_Point := Midpoint (Next, After);
                  begin
                     Add_Quadratic
                       (Segments => Segments,
                        X0       => Current.X,
                        Y0       => Current.Y,
                        CX       => Next.X,
                        CY       => Next.Y,
                        X1       => Implied.X,
                        Y1       => Implied.Y);

                     Current := Implied;
                     I := I + 1;
                  end;
               end if;
            end if;
         end loop;

         --  Explicitly close the contour.
         if Current.X /= Start_Point.X or else Current.Y /= Start_Point.Y then
            Add_Segment
              (Segments => Segments,
               X0       => Current.X,
               Y0       => Current.Y,
               X1       => Start_Point.X,
               Y1       => Start_Point.Y);
         end if;
      end Build_Contour;

      --  The segments a subsample row crosses. Rows come top down, so the
      --  segments, sorted by their tops, are swept: one opens once the row is
      --  below its top, and closes for good once the row is below its bottom.
      --  A segment is active exactly as it was found before, by testing every
      --  segment; only the order of the active ones differs, which a winding
      --  number, a sum, does not see.
      procedure Build_Active_Segments
        (Sample_Y : Float)
      is
         Kept : Natural := Open_Segments.First_Index;
      begin
         Active_Segments.Clear;

         --  Element, not indexing: an indexed read of a vector goes through a
         --  reference whose controlled tamper lock is finalized at every read.
         while Next_Segment <= Segments.Last_Index
           and then Float'Max (Segments.Element (Next_Segment).Y0, Segments.Element (Next_Segment).Y1) > Sample_Y
         loop
            Open_Segments.Append (Segments.Element (Next_Segment));
            Next_Segment := Next_Segment + 1;
         end loop;

         for I in Open_Segments.First_Index .. Open_Segments.Last_Index loop
            declare
               S : constant Segment := Open_Segments.Element (I);
            begin
               if (S.Y0 <= Sample_Y and then S.Y1 > Sample_Y)
                 or else
                  (S.Y0 > Sample_Y and then S.Y1 <= Sample_Y)
               then
                  Active_Segments.Append
                    (Active_Edge'(Fixed_Term => (S.X1 - S.X0) * (Sample_Y - S.Y0),
                                  X0         => S.X0,
                                  Rise       => S.Y1 - S.Y0,
                                  Upward     => S.Y0 <= Sample_Y));
                  Open_Segments.Replace_Element (Kept, S);
                  Kept := Kept + 1;
               end if;
            end;
         end loop;
         --  An open segment the row does not cross is wholly above it, and so
         --  above every later row.
         Open_Segments.Set_Length (Ada.Containers.Count_Type (Kept - Open_Segments.First_Index));
      end Build_Active_Segments;

      --  The winding number of the point PX on the row the active edges were
      --  built for: an upward edge with the point on its left counts one, a
      --  downward edge with the point on its right minus one.
      function Inside_Active
        (PX : Float) return Boolean
      is
         Winding : Integer := 0;
      begin
         for A in Active_Segments.First_Index .. Active_Segments.Last_Index loop
            declare
               E    : constant Active_Edge := Active_Segments.Element (A);
               Left : constant Float := E.Fixed_Term - (PX - E.X0) * E.Rise;
            begin
               if E.Upward then
                  if Left > 0.0 then
                     Winding := Winding + 1;
                  end if;
               elsif Left < 0.0 then
                  Winding := Winding - 1;
               end if;
            end;
         end loop;

         return Winding /= 0;
      end Inside_Active;

   begin
      Prepare_Buffers;

      if Glyph_Index >= Textrender.Fonts.Num_Glyphs (F) then
         return False;
      end if;

      if not Textrender.Fonts.Glyph_Data_Range
        (F           => F,
         Glyph_Index => Glyph_Index,
         First       => G0,
         Last        => G1)
      then
         return False;
      end if;

      if G1 < G0 then
         return False;
      elsif G1 = G0 then
         return True;
      end if;

      if not Textrender.Fonts.Has_Bytes (F, G0, 10) then
         return False;
      end if;

      Number_Of_Contours := Textrender.Fonts.I16 (F, G0);

      if Number_Of_Contours < 0 then
         return True;
      end if;

      if Number_Of_Contours = 0 then
         return True;
      end if;

      Contour_Count := Natural (Number_Of_Contours);

      End_Points_Off := G0 + 10;

      if not Textrender.Fonts.Has_Bytes
        (F, End_Points_Off, Contour_Count * 2 + 2)
      then
         return False;
      end if;

      for I in 0 .. Contour_Count - 1 loop
         End_Points.Append
         (Textrender.Fonts.U16 (F, End_Points_Off + I * 2));
      end loop;

      Point_Count := End_Points (Contour_Count - 1) + 1;

      if Point_Count = 0 then
         return True;
      end if;

      Instr_Len_Off := End_Points_Off + Contour_Count * 2;
      Instr_Len     := Textrender.Fonts.U16 (F, Instr_Len_Off);
      if Instr_Len > 10_000 then
         return False;
      end if;
      Off           := Instr_Len_Off + 2 + Instr_Len;

      if Off > G1 then
         return False;
      end if;

      Flags.Reserve_Capacity  (Ada.Containers.Count_Type (Point_Count));
      Xs.Reserve_Capacity     (Ada.Containers.Count_Type (Point_Count));
      Ys.Reserve_Capacity     (Ada.Containers.Count_Type (Point_Count));
      Points.Reserve_Capacity (Ada.Containers.Count_Type (Point_Count));
      for I in 0 .. Point_Count - 1 loop
            Flags.Append (0);
            Xs.Append (0);
            Ys.Append (0);
            Points.Append (Glyph_Point'(X => 0.0, Y => 0.0, On_Curve => False));
      end loop;
      P := 0;

      while P < Point_Count loop
         if not Textrender.Fonts.Has_Bytes (F, Off, 1) then
            return False;
         end if;

         Flag_Value := Textrender.Fonts.Byte_At (F, Off);
         Off := Off + 1;

         Flags (P) := Flag_Value;
         P := P + 1;

         if Bit_Set (Flag_Value, 16#08#) then
            if not Textrender.Fonts.Has_Bytes (F, Off, 1) then
               return False;
            end if;

            Repeat_N := Textrender.Fonts.Byte_At (F, Off);
            Off := Off + 1;

            for R in 1 .. Repeat_N loop
               if P >= Point_Count then
                  return False;
               end if;

               Flags (P) := Flag_Value;
               P := P + 1;
            end loop;
         end if;
      end loop;

      for I in 0 .. Point_Count - 1 loop
         if Bit_Set (Flags (I), 16#02#) then
            if not Textrender.Fonts.Has_Bytes (F, Off, 1) then
               return False;
            end if;

            if Bit_Set (Flags (I), 16#10#) then
               DX := Integer (Textrender.Fonts.Byte_At (F, Off));
            else
               DX := -Integer (Textrender.Fonts.Byte_At (F, Off));
            end if;

            Off := Off + 1;
         else
            if Bit_Set (Flags (I), 16#10#) then
               DX := 0;
            else
               if not Textrender.Fonts.Has_Bytes (F, Off, 2) then
                  return False;
               end if;

               DX := Textrender.Fonts.I16 (F, Off);
               Off := Off + 2;
            end if;
         end if;

         X := X + DX;
         Xs (I) := X;
      end loop;

      for I in 0 .. Point_Count - 1 loop
         if Bit_Set (Flags (I), 16#04#) then
            if not Textrender.Fonts.Has_Bytes (F, Off, 1) then
               return False;
            end if;

            if Bit_Set (Flags (I), 16#20#) then
               DY := Integer (Textrender.Fonts.Byte_At (F, Off));
            else
               DY := -Integer (Textrender.Fonts.Byte_At (F, Off));
            end if;

            Off := Off + 1;
         else
            if Bit_Set (Flags (I), 16#20#) then
               DY := 0;
            else
               if not Textrender.Fonts.Has_Bytes (F, Off, 2) then
                  return False;
               end if;

               DY := Textrender.Fonts.I16 (F, Off);
               Off := Off + 2;
            end if;
         end if;

         Y := Y + DY;
         Ys (I) := Y;
      end loop;

      for I in 0 .. Point_Count - 1 loop
         declare
            aXs : constant Integer := Xs (I);
            aYs : constant Integer := Ys (I);
            P2 : constant Glyph_Point :=
              Apply
                (T => Transform,
                 X => Float (aXs),
                 Y => Float (aYs));
         begin
            Points (I) :=
              (X        => P2.X,
               Y        => P2.Y,
               On_Curve => Bit_Set (Flags (I), 16#01#));
         end;
      end loop;

      declare
         First : Natural := 0;
      begin
         for C in 0 .. Contour_Count - 1 loop
            Build_Contour
              (First => First,
               Last  => End_Points (C));

            First := End_Points (C) + 1;
         end loop;
      end;
      --  Segments is the accumulator; a stubbed-out "Segment_Count : constant
      --  Natural := 0" used to stand here, which made this assertion state
      --  0 > 0 and fail unconditionally whenever assertions were enabled.
      pragma Assert
        (not Segments.Is_Empty,
         "No segments generated for non-empty simple glyph");
      --  Top down, for the sweep that finds each subsample row's segments.
      Top_Down.Sort (Segments);
      declare
         Samples_Per_Axis : constant Positive := 8;
         Total_Samples    : constant Positive :=
           Samples_Per_Axis * Samples_Per_Axis;
      begin
         --  A row of pixels at a time: the edges a subsample row crosses are found once for the whole row, not
         --  once for each pixel of it, and each pixel counts its covered samples as before.
         for PY in 0 .. Glyph_H - 1 loop
            declare
               type Sample_Counts is array (0 .. Glyph_W - 1) of Natural;
               Covered : Sample_Counts := [others => 0];
            begin
               for SY in 0 .. Samples_Per_Axis - 1 loop
                  declare
                     Font_Y : constant Float :=
                       Float (Y_Max)
                       - (Float (PY)
                          + (Float (SY) + 0.5)
                            / Float (Samples_Per_Axis))
                         / Scale;
                  begin
                     Build_Active_Segments (Sample_Y => Font_Y);
                     if not Active_Segments.Is_Empty then
                        for PX in 0 .. Glyph_W - 1 loop
                           for SX in 0 .. Samples_Per_Axis - 1 loop
                              declare
                                 Font_X : constant Float :=
                                   Float (X_Min)
                                   + (Float (PX)
                                      + (Float (SX) + 0.5)
                                        / Float (Samples_Per_Axis))
                                     / Scale;
                              begin
                                 if Inside_Active (PX => Font_X) then
                                    Covered (PX) := Covered (PX) + 1;
                                 end if;
                              end;
                           end loop;
                        end loop;
                     end if;
                  end;
               end loop;
               for PX in 0 .. Glyph_W - 1 loop
                  if Atlas_X + PX < Textrender.Atlases.Width (A)
                     and then Atlas_Y + PY < Textrender.Atlases.Height (A)
                  then
                     Textrender.Atlases.Blend_Max
                       (A     => A,
                        X     => Atlas_X + PX,
                        Y     => Atlas_Y + PY,
                        Value =>
                          Textrender.Atlases.Alpha
                            ((Covered (PX) * 255) / Total_Samples));
                  end if;
               end loop;
            end;
         end loop;
      end;

      return True;

   exception
      when others =>
         return False;
   end Rasterize_Simple_Glyph;

   function Rasterize_Glyph
     (F           : Textrender.Fonts.Font;
      A           : in out Textrender.Atlases.Atlas;
      Glyph_Index : Natural;
      Atlas_X     : Natural;
      Atlas_Y     : Natural;
      Glyph_W     : Positive;
      Glyph_H     : Positive;
      X_Min       : Integer;
      Y_Min       : Integer;
      X_Max       : Integer;
      Y_Max       : Integer;
      Pixel_Size  : Positive;
      Transform   : Glyph_Transform := Identity_Transform) return Boolean
   is
      G0 : Natural;
      G1 : Natural;

      Number_Of_Contours : Integer;

      Flags           : Natural;
      Component_Glyph : Natural;

      Off : Natural;

      Arg1 : Integer;
      Arg2 : Integer;

      Args_Are_Words  : Boolean;
      Args_Are_XY     : Boolean;
      More_Components : Boolean;

      Has_Scale    : Boolean;
      Has_XY_Scale : Boolean;
      Has_2x2      : Boolean;

      Component_Transform : Glyph_Transform;
   begin
      if Glyph_Index >= Textrender.Fonts.Num_Glyphs (F) then
         return False;
      end if;

      if not Textrender.Fonts.Glyph_Data_Range
        (F           => F,
         Glyph_Index => Glyph_Index,
         First       => G0,
         Last        => G1)
      then
         return False;
      end if;

      if G1 < G0 then
         return False;
      elsif G1 = G0 then
         return True;
      end if;

      if not Textrender.Fonts.Has_Bytes (F, G0, 10) then
         return False;
      end if;

      Number_Of_Contours := Textrender.Fonts.I16 (F, G0);

      if Number_Of_Contours >= 0 then
         return Rasterize_Simple_Glyph
           (F           => F,
            A           => A,
            Glyph_Index => Glyph_Index,
            Atlas_X     => Atlas_X,
            Atlas_Y     => Atlas_Y,
            Glyph_W     => Glyph_W,
            Glyph_H     => Glyph_H,
            X_Min       => X_Min,
            Y_Min       => Y_Min,
            X_Max       => X_Max,
            Y_Max       => Y_Max,
            Pixel_Size  => Pixel_Size,
            Transform   => Transform);
      end if;

      Off := G0 + 10;

      loop
         if not Textrender.Fonts.Has_Bytes (F, Off, 4) then
            return False;
         end if;

         Flags           := Textrender.Fonts.U16 (F, Off);
         Component_Glyph := Textrender.Fonts.U16 (F, Off + 2);
         Off := Off + 4;

         Args_Are_Words  := Bit_Set (Flags, 16#0001#);
         Args_Are_XY     := Bit_Set (Flags, 16#0002#);
         More_Components := Bit_Set (Flags, 16#0020#);

         Has_Scale    := Bit_Set (Flags, 16#0008#);
         Has_XY_Scale := Bit_Set (Flags, 16#0040#);
         Has_2x2      := Bit_Set (Flags, 16#0080#);

         if not Args_Are_XY then
            return False;
         end if;

         if Args_Are_Words then
            if not Textrender.Fonts.Has_Bytes (F, Off, 4) then
               return False;
            end if;

            Arg1 := Textrender.Fonts.I16 (F, Off);
            Arg2 := Textrender.Fonts.I16 (F, Off + 2);
            Off := Off + 4;
         else
            if not Textrender.Fonts.Has_Bytes (F, Off, 2) then
               return False;
            end if;

            declare
               B1 : constant Natural := Textrender.Fonts.Byte_At (F, Off);
               B2 : constant Natural := Textrender.Fonts.Byte_At (F, Off + 1);
            begin
               if B1 >= 128 then
                  Arg1 := Integer (B1) - 256;
               else
                  Arg1 := Integer (B1);
               end if;

               if B2 >= 128 then
                  Arg2 := Integer (B2) - 256;
               else
                  Arg2 := Integer (B2);
               end if;
            end;

            Off := Off + 2;
         end if;

         Component_Transform := Transform;

         declare
            M00 : Float := 1.0;
            M01 : Float := 0.0;
            M10 : Float := 0.0;
            M11 : Float := 1.0;
         begin
            if Has_Scale then
               if not Textrender.Fonts.Has_Bytes (F, Off, 2) then
                  return False;
               end if;

               M00 := Float (Textrender.Fonts.I16 (F, Off)) / 16384.0;
               M11 := M00;
               Off := Off + 2;

            elsif Has_XY_Scale then
               if not Textrender.Fonts.Has_Bytes (F, Off, 4) then
                  return False;
               end if;

               M00 := Float (Textrender.Fonts.I16 (F, Off)) / 16384.0;
               M11 := Float (Textrender.Fonts.I16 (F, Off + 2)) / 16384.0;
               Off := Off + 4;

            elsif Has_2x2 then
               if not Textrender.Fonts.Has_Bytes (F, Off, 8) then
                  return False;
               end if;

               M00 := Float (Textrender.Fonts.I16 (F, Off)) / 16384.0;
               M01 := Float (Textrender.Fonts.I16 (F, Off + 2)) / 16384.0;
               M10 := Float (Textrender.Fonts.I16 (F, Off + 4)) / 16384.0;
               M11 := Float (Textrender.Fonts.I16 (F, Off + 6)) / 16384.0;
               Off := Off + 8;
            end if;

            Component_Transform.XX :=
              Transform.XX * M00 + Transform.XY * M10;

            Component_Transform.XY :=
              Transform.XX * M01 + Transform.XY * M11;

            Component_Transform.YX :=
              Transform.YX * M00 + Transform.YY * M10;

            Component_Transform.YY :=
              Transform.YX * M01 + Transform.YY * M11;

            Component_Transform.DX :=
              Transform.XX * Float (Arg1)
              + Transform.XY * Float (Arg2)
              + Transform.DX;

            Component_Transform.DY :=
              Transform.YX * Float (Arg1)
              + Transform.YY * Float (Arg2)
              + Transform.DY;
         end;

         if not Rasterize_Glyph
           (F           => F,
            A           => A,
            Glyph_Index => Component_Glyph,
            Atlas_X     => Atlas_X,
            Atlas_Y     => Atlas_Y,
            Glyph_W     => Glyph_W,
            Glyph_H     => Glyph_H,
            X_Min       => X_Min,
            Y_Min       => Y_Min,
            X_Max       => X_Max,
            Y_Max       => Y_Max,
            Pixel_Size  => Pixel_Size,
            Transform   => Component_Transform)
         then
            return False;
         end if;

         exit when not More_Components;
      end loop;

      return True;
   end Rasterize_Glyph;

end Textrender.Rasterizer;