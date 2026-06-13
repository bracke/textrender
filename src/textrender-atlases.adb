with Ada.Unchecked_Deallocation;

package body Textrender.Atlases is

   procedure Free is new Ada.Unchecked_Deallocation
     (Alpha_Buffer, Alpha_Buffer_Access);

   -----------------------------
   -- Init
   -----------------------------

   procedure Init
     (A      : in out Atlas;
      Width  : Positive;
      Height : Positive)
   is
      Size : Natural := Width * Height;
   begin
      Reset (A);

      A.Width_V  := Width;
      A.Height_V := Height;

      A.Data := new Alpha_Buffer (0 .. Size - 1);

      Clear (A);

      A.Next_X     := 0;
      A.Next_Y     := 0;
      A.Row_Height := 0;
   end Init;

   -----------------------------
   -- Reset
   -----------------------------

   procedure Reset (A : in out Atlas) is
   begin
      if A.Data /= null then
         Free (A.Data);
         A.Data := null;
      end if;

      A.Width_V  := 1;
      A.Height_V := 1;

      A.Next_X     := 0;
      A.Next_Y     := 0;
      A.Row_Height := 0;
   end Reset;

   -----------------------------
   -- Dimensions
   -----------------------------

   function Width (A : Atlas) return Positive is
   begin
      return A.Width_V;
   end Width;

   function Height (A : Atlas) return Positive is
   begin
      return A.Height_V;
   end Height;

   -----------------------------
   -- Pixels
   -----------------------------

   function Pixels
     (A : Atlas) return access constant Alpha_Buffer
   is
   begin
      return A.Data;
   end Pixels;

   -----------------------------
   -- Clear
   -----------------------------

   procedure Clear (A : in out Atlas) is
   begin
      if A.Data /= null then
         for I in A.Data'Range loop
            A.Data (I) := 0;
         end loop;
      end if;
   end Clear;

   -----------------------------
   -- Allocate_Rect
   -----------------------------

   function Allocate_Rect
     (A : in out Atlas;
      W : Positive;
      H : Positive;
      X : out Natural;
      Y : out Natural) return Boolean
   is
   begin
      if W > A.Width_V or else H > A.Height_V then
         return False;
      end if;

      if A.Next_X + W > A.Width_V then
         A.Next_X     := 0;
         A.Next_Y     := A.Next_Y + A.Row_Height;
         A.Row_Height := 0;
      end if;

      if A.Next_Y + H > A.Height_V then
         return False;
      end if;

      X := A.Next_X;
      Y := A.Next_Y;

      A.Next_X := A.Next_X + W;

      if H > A.Row_Height then
         A.Row_Height := H;
      end if;

      return True;
   end Allocate_Rect;

   -----------------------------
   -- Write_Pixel
   -----------------------------

   procedure Write_Pixel
     (A : in out Atlas;
      X : Natural;
      Y : Natural;
      Value : Alpha)
   is
      Index : Natural;
   begin
      if A.Data = null then
         return;
      end if;

      if X >= A.Width_V or else Y >= A.Height_V then
         return;
      end if;

      Index := Y * A.Width_V + X;

      A.Data (Index) := Value;
   end Write_Pixel;

   -----------------------------
   -- Blend_Max
   -----------------------------

   procedure Blend_Max
     (A : in out Atlas;
      X : Natural;
      Y : Natural;
      Value : Alpha)
   is
      Index : Natural;
   begin
      if A.Data = null then
         return;
      end if;

      if X >= A.Width_V or else Y >= A.Height_V then
         return;
      end if;

      Index := Y * A.Width_V + X;

      if Value > A.Data (Index) then
         A.Data (Index) := Value;
      end if;
   end Blend_Max;

end Textrender.Atlases;