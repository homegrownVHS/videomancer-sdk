library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package core_config_pkg is
  constant C_ENABLE_ANALOG   : boolean := true;
  constant C_ENABLE_HDMI     : boolean := false;
  constant C_ENABLE_DUAL    : boolean := false;
  constant C_ENABLE_SD       : boolean := false;
  constant C_ENABLE_HD       : boolean := true;
  constant C_HD_CLOCK_DIVISOR : integer := 1;
end package core_config_pkg;