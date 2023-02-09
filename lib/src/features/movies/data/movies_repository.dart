import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tmdb_movie_app_riverpod/env/env.dart';
import 'package:tmdb_movie_app_riverpod/src/features/movies/data/movies_pagination.dart';
import 'package:tmdb_movie_app_riverpod/src/features/movies/domain/tmdb_movie.dart';
import 'package:tmdb_movie_app_riverpod/src/features/movies/domain/tmdb_movies_response.dart';
import 'package:tmdb_movie_app_riverpod/src/utils/cancel_token_ref.dart';
import 'package:tmdb_movie_app_riverpod/src/utils/dio_provider.dart';

part 'movies_repository.g.dart';

class MoviesRepository {
  MoviesRepository({required this.client, required this.apiKey});
  final Dio client;
  final String apiKey;

  Future<List<TMDBMovie>> searchMovies(
      {required int page, String query = '', CancelToken? cancelToken}) async {
    final url = Uri(
      scheme: 'https',
      host: 'api.themoviedb.org',
      path: '3/search/movie',
      queryParameters: {
        'api_key': apiKey,
        'include_adult': 'false',
        'page': '$page',
        'query': query,
      },
    ).toString();
    final response = await client.get(url, cancelToken: cancelToken);
    final movies = TMDBMoviesResponse.fromJson(response.data);
    return movies.results;
  }

  Future<List<TMDBMovie>> nowPlayingMovies(
      {required int page, CancelToken? cancelToken}) async {
    final url = Uri(
      scheme: 'https',
      host: 'api.themoviedb.org',
      path: '3/movie/now_playing',
      queryParameters: {
        'api_key': apiKey,
        'include_adult': 'false',
        'page': '$page',
      },
    ).toString();
    final response = await client.get(url, cancelToken: cancelToken);
    final movies = TMDBMoviesResponse.fromJson(response.data);
    return movies.results;
  }

  Future<TMDBMovie> movie(
      {required int movieId, CancelToken? cancelToken}) async {
    final url = Uri(
      scheme: 'https',
      host: 'api.themoviedb.org',
      path: '3/movie/$movieId',
      queryParameters: {
        'api_key': apiKey,
        'include_adult': 'false',
      },
    ).toString();
    final response = await client.get(url, cancelToken: cancelToken);
    return TMDBMovie.fromJson(response.data);
  }
}

@riverpod
MoviesRepository moviesRepository(MoviesRepositoryRef ref) => MoviesRepository(
      client: ref.watch(dioProvider),
      apiKey: Env.tmdbApiKey,
    );

class AbortedException implements Exception {}

/// Provider to fetch a movie by ID
@riverpod
Future<TMDBMovie> movie(
  MovieRef ref, {
  required int movieId,
}) {
  final cancelToken = ref.cancelToken();
  return ref
      .watch(moviesRepositoryProvider)
      .movie(movieId: movieId, cancelToken: cancelToken);
}

/// Provider to fetch paginated movies data
@riverpod
Future<List<TMDBMovie>> fetchMovies(
  FetchMoviesRef ref, {
  required MoviesPagination pagination,
}) async {
  final moviesRepo = ref.watch(moviesRepositoryProvider);
  // See this for how the timeout is implemented:
  // https://codewithandrea.com/articles/flutter-riverpod-data-caching-providers-lifecycle/#caching-with-timeout
  // Cancel the page request if the UI no longer needs it.
  // This happens if the user scrolls very fast or if we type a different search
  // term.
  final cancelToken = CancelToken();
  // When a page is no-longer used, keep it in the cache.
  final link = ref.keepAlive();
  // a timer to be used by the callbacks below
  Timer? timer;
  // When the provider is destroyed, cancel the http request and the timer
  ref.onDispose(() {
    cancelToken.cancel();
    timer?.cancel();
  });
  // When the last listener is removed, start a timer to dispose the cached data
  ref.onCancel(() {
    // start a 30 second timer
    timer = Timer(const Duration(seconds: 30), () {
      // dispose on timeout
      link.close();
    });
  });
  // If the provider is listened again after it was paused, cancel the timer
  ref.onResume(() {
    timer?.cancel();
  });
  if (pagination.query.isEmpty) {
    // use non-search endpoint
    return moviesRepo.nowPlayingMovies(
      page: pagination.page,
      cancelToken: cancelToken,
    );
  } else {
    // Debounce the request. By having this delay, consumers can subscribe to
    // different parameters. In which case, this request will be aborted.
    await Future.delayed(const Duration(milliseconds: 500));
    if (cancelToken.isCancelled) throw AbortedException();
    // use search endpoint
    return moviesRepo.searchMovies(
      page: pagination.page,
      query: pagination.query,
      cancelToken: cancelToken,
    );
  }
}
