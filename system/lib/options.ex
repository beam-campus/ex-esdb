defmodule ExESDB.Options do
  @moduledoc """
    This module contains the options helper functions for ExESDB
  """
  alias ExESDB.EnVars, as: EnVars

  @data_dir EnVars.data_dir()
  @store_id EnVars.store_id()
  @timeout EnVars.timeout()
  @db_type EnVars.db_type()
  @pub_sub EnVars.pub_sub()
  @writer_idle_ms EnVars.writer_idle_ms()
  @reader_idle_ms EnVars.reader_idle_ms()
  @store_description EnVars.store_description()
  @store_tags EnVars.store_tags()

  def sys_env(key), do: System.get_env(key)
  def app_env, do: Application.get_env(:ex_esdb, :khepri)
  def app_env(key), do: Keyword.get(app_env(), key)

  def topologies, do: Application.get_env(:libcluster, :topologies)

  def data_dir do
    case sys_env(@data_dir) do
      nil -> app_env(:data_dir) || "/data"
      data_dir -> data_dir
    end
  end

  def store_id do
    case sys_env(@store_id) do
      nil -> app_env(:store_id) || :ex_esdb_store
      store_id -> to_unique_atom(store_id)
    end
  end

  def timeout do
    case sys_env(@timeout) do
      nil -> app_env(:timeout) || 10_000
      timeout -> String.to_integer(timeout)
    end
  end

  def db_type do
    case sys_env(@db_type) do
      nil -> app_env(:db_type) || :single
      db_type -> String.to_atom(db_type)
    end
  end


  def pub_sub do
    case sys_env(@pub_sub) do
      nil -> app_env(:pub_sub) || :native
      pub_sub -> to_unique_atom(pub_sub)
    end
  end

  def reader_idle_ms do
    case sys_env(@reader_idle_ms) do
      nil -> app_env(:reader_idle_ms) || 10_000
      reader_idle_ms -> String.to_integer(reader_idle_ms)
    end
  end

  def writer_idle_ms do
    case sys_env(@writer_idle_ms) do
      nil -> app_env(:writer_idle_ms) || 10_000
      writer_idle_ms -> String.to_integer(writer_idle_ms)
    end
  end

  def store_description do
    case sys_env(@store_description) do
      nil -> app_env(:store_description)
      store_description -> store_description
    end
  end

  def store_tags do
    case sys_env(@store_tags) do
      nil -> 
        app_env(:store_tags) || []
      tags_string -> 
        tags_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp to_unique_atom(candidate) do
    try do
      String.to_existing_atom(candidate)
    rescue
      _ -> String.to_atom(candidate)
    end
  end
end
