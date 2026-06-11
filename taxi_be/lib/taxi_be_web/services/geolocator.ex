defmodule TaxiBeWeb.Geolocator do
  require Logger

  @geocodingURL "https://api.mapbox.com/geocoding/v5/mapbox.places/"
  @directionsURL "https://api.mapbox.com/directions/v5/mapbox/driving/"
  @distanceMatrixURL "https://api.mapbox.com/directions-matrix/v1/mapbox/driving/"
  @token System.get_env("MAPBOX_TOKEN") || "pk.test_token"

  def geocode(address) do
    case HTTPoison.get(
      @geocodingURL <> URI.encode(address) <>
      ".json?access_token=" <> @token
    ) do
      {:ok, %{body: bodyStr}} ->
        { :ok,
          bodyStr
          |> Jason.decode!
          |> Map.fetch!("features")
          |> hd
          |> Map.fetch!("center")
        }
      _ -> {:error, "Something wrong with Mapbox call"}
    end
  end

  def distance_and_duration({_, origin_coord}, {_, destination_coord}) do
    %{body: body} =
      HTTPoison.get!(
        @directionsURL <>
        "#{Enum.join(origin_coord, ",")};#{Enum.join(destination_coord, ",")}" <>
        "?access_token=" <> @token)

    %{"duration" => duration, "distance" => distance} =
      body
      |> Jason.decode!
      |> Map.fetch!("routes")
      |> hd
    {distance, duration}
  end

  def destination_and_duration(driver_coords, destination_coords) do
    list_of_coords = [destination_coords|driver_coords]
    %{body: body} = HTTPoison.get!(@distanceMatrixURL <>
      "#{
        Enum.map(list_of_coords, fn coords -> Enum.join(coords, ",") end)
        |> Enum.join(";")}" <>
      "?sources=0&access_token=" <> @token)

    body
    |> Jason.decode!
    |> Map.fetch!("durations")
    |> List.flatten
    |> tl
  end

  def find_nearest_drivers(customer_location, drivers, count \\ 3) do
    drivers_with_distance = Enum.map(drivers, fn driver ->
      distance = calculate_simple_distance(customer_location, driver["location"])
      {driver, distance}
    end)

    drivers_with_distance
    |> Enum.sort_by(fn {_driver, distance} -> distance end)
    |> Enum.take(count)
    |> Enum.map(fn {driver, _distance} -> driver end)
  end

  # Simple distance calculation without Mapbox call (for speed)
  # In production, use the Mapbox API
  defp calculate_simple_distance([lon1, lat1], [lon2, lat2]) do
    # Haversine formula for quick distance calculation
    r = 6371  # Earth radius in km
    dlat = (lat2 - lat1) * :math.pi() / 180
    dlon = (lon2 - lon1) * :math.pi() / 180
    a = :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1 * :math.pi() / 180) * :math.cos(lat2 * :math.pi() / 180) *
        :math.sin(dlon / 2) * :math.sin(dlon / 2)
    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    r * c
  end

  defp calculate_simple_distance(_loc1, _loc2) do
    # Default distance if locations are invalid
    999999
  end
end
