# frozen_string_literal: true

module Api
  module V1
    # Exposes market data for the dashboard
    class MarketDataController < BaseController
      # GET /api/v1/market_data/current
      # Returns current prices and indicators for all assets
      def current
        snapshots = MarketSnapshot.latest_per_symbol

        render json: {
          assets: snapshots.map { |s| serialize_snapshot(s) },
          updated_at: snapshots.map(&:captured_at).max&.iso8601
        }
      end

      # GET /api/v1/market_data/:symbol
      # Returns current data for a specific asset
      def show
        symbol = params[:symbol].upcase
        snapshot = MarketSnapshot.latest_for(symbol)

        if snapshot
          render json: { asset: serialize_snapshot(snapshot, detailed: true) }
        else
          render json: { error: "No data for #{symbol}" }, status: :not_found
        end
      end

      # GET /api/v1/market_data/:symbol/history
      # Returns historical price data for charting
      def history
        symbol = params[:symbol].upcase
        hours = (params[:hours] || 24).to_i.clamp(1, 168)
        interval = params[:interval] || "5m"

        snapshots = MarketSnapshot.for_symbol(symbol)
                                  .last_hours(hours)
                                  .order(captured_at: :asc)

        # Aggregate based on interval if needed
        data = aggregate_snapshots(snapshots, interval)

        render json: {
          symbol: symbol,
          interval: interval,
          data: data
        }
      end

      # GET /api/v1/market_data/forecasts
      # Returns latest forecasts for all assets
      def forecasts
        forecasts_data = Settings.assets.to_h do |symbol|
          forecasts = Forecast::VALID_TIMEFRAMES.to_h do |tf|
            forecast = Forecast.latest_for(symbol, tf)
            [ tf, forecast ? serialize_forecast(forecast) : nil ]
          end.compact
          [ symbol, forecasts ]
        end

        render json: { forecasts: forecasts_data }
      end

      # GET /api/v1/market_data/:symbol/forecasts
      def symbol_forecasts
        symbol = params[:symbol].upcase

        unless Forecast::VALID_SYMBOLS.include?(symbol)
          return render json: { error: "Invalid symbol" }, status: :bad_request
        end

        forecasts = Forecast::VALID_TIMEFRAMES.to_h do |tf|
          forecast = Forecast.latest_for(symbol, tf)
          [ tf, forecast ? serialize_forecast(forecast) : nil ]
        end.compact

        # Include forecast accuracy if available
        recent_validated = Forecast.for_symbol(symbol)
                                   .validated
                                   .order(created_at: :desc)
                                   .limit(20)

        avg_mape = recent_validated.average(:mape)&.to_f&.round(2)

        render json: {
          symbol: symbol,
          forecasts: forecasts,
          accuracy: {
            avg_mape: avg_mape,
            sample_size: recent_validated.count
          }
        }
      end

      private

      def serialize_snapshot(snapshot, detailed: false)
        indicators = snapshot.indicators || {}

        data = {
          symbol: snapshot.symbol,
          price: snapshot.price.to_f,
          captured_at: snapshot.captured_at.iso8601,
          rsi_14: indicators["rsi_14"]&.round(2),
          rsi_signal: snapshot.rsi_signal,
          macd_signal: snapshot.macd_signal,
          ema_20: indicators["ema_20"]&.round(2),
          ema_50: indicators["ema_50"]&.round(2),
          ema_100: indicators["ema_100"]&.round(2),
          above_ema_20: snapshot.above_ema?(20),
          above_ema_50: snapshot.above_ema?(50)
        }

        if detailed
          data[:indicators] = indicators
          data[:macd] = indicators["macd"]
          data[:pivot_points] = indicators["pivot_points"]
          data[:sentiment] = snapshot.sentiment
        end

        data
      end

      def serialize_forecast(forecast)
        {
          current_price: forecast.current_price.to_f,
          predicted_price: forecast.predicted_price.to_f,
          direction: forecast.direction,
          change_pct: forecast.predicted_change_pct,
          forecast_for: forecast.forecast_for.iso8601,
          created_at: forecast.created_at.iso8601
        }
      end

      def aggregate_snapshots(snapshots, interval)
        return snapshots.map { |s| snapshot_to_ohlc(s) } if snapshots.count < 100

        # Group by interval
        interval_minutes = parse_interval(interval)
        grouped = snapshots.group_by do |s|
          (s.captured_at.to_i / (interval_minutes * 60)) * (interval_minutes * 60)
        end

        grouped.map do |timestamp, group|
          prices = group.map(&:price)
          {
            time: Time.at(timestamp).iso8601,
            open: group.first.price.to_f,
            high: prices.max.to_f,
            low: prices.min.to_f,
            close: group.last.price.to_f,
            volume: group.size
          }
        end
      end

      def snapshot_to_ohlc(snapshot)
        {
          time: snapshot.captured_at.iso8601,
          open: snapshot.price.to_f,
          high: snapshot.price.to_f,
          low: snapshot.price.to_f,
          close: snapshot.price.to_f
        }
      end

      def parse_interval(interval)
        case interval
        when "1m" then 1
        when "5m" then 5
        when "15m" then 15
        when "1h" then 60
        when "4h" then 240
        else 5
        end
      end
    end
  end
end
