defmodule ExESDB.Khepri.Conditions do
  @moduledoc false
  import Record

  @khepri_hrl "khepri/include/khepri.hrl"
  defrecord :if_name_matches,
            extract(:if_name_matches, from_lib: @khepri_hrl)

  defrecord :if_path_matches,
            extract(:if_path_matches, from_lib: @khepri_hrl)

  defrecord :if_has_payload,
            extract(:if_has_payload, from_lib: @khepri_hrl)

  defrecord :if_has_data,
            extract(:if_has_data, from_lib: @khepri_hrl)

  defrecord :if_has_sproc,
            extract(:if_has_sproc, from_lib: @khepri_hrl)

  defrecord :if_data_matches,
            extract(:if_data_matches, from_lib: @khepri_hrl)

  defrecord :if_node_exists,
            extract(:if_node_exists, from_lib: @khepri_hrl)

  defrecord :if_payload_version,
            extract(:if_payload_version, from_lib: @khepri_hrl)

  defrecord :if_child_list_version,
            extract(:if_child_list_version, from_lib: @khepri_hrl)

  defrecord :if_child_list_length,
            extract(:if_child_list_length, from_lib: @khepri_hrl)

  defrecord :if_not,
            extract(:if_not, from_lib: @khepri_hrl)

  defrecord :if_all,
            extract(:if_all, from_lib: @khepri_hrl)

  defrecord :if_any,
            extract(:if_any, from_lib: @khepri_hrl)
end
