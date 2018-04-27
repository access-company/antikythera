use Croma

defmodule <%= gear_name_camel %>.Gettext do
  use SolomonLib.Gettext, otp_app: :<%= gear_name %>

  defun put_locale(locale :: v[String.t]) :: nil do
    Gettext.put_locale(__MODULE__, locale)
  end
end
