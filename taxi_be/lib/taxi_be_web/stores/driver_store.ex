defmodule TaxiBeWeb.DriverStore do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def register_driver(driver_id, driver_data) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, driver_id, Map.put(driver_data, "id", driver_id))
    end)
    get_driver(driver_id)
  end

  def get_driver(driver_id) do
    Agent.get(__MODULE__, fn state -> Map.get(state, driver_id) end)
  end

  def update_driver(driver_id, updates) do
    Agent.update(__MODULE__, fn state ->
      case Map.get(state, driver_id) do
        nil -> state
        driver -> Map.put(state, driver_id, Map.merge(driver, updates))
      end
    end)
    get_driver(driver_id)
  end

  def list_drivers do
    Agent.get(__MODULE__, fn state -> Map.values(state) end)
  end

  def list_available_drivers do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.values()
      |> Enum.filter(fn driver -> driver["available"] == true end)
    end)
  end

  def unregister_driver(driver_id) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, driver_id) end)
  end
end
