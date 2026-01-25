import 'package:flutter/material.dart';
import 'package:my_first_app/service/wp_api_service.dart';
import 'package:my_first_app/model/character.dart';

class TekkenCharacterListScreen extends StatefulWidget {
  const TekkenCharacterListScreen({super.key});

  @override
  State<TekkenCharacterListScreen> createState() =>
      _TekkenCharacterListScreenState();
}

class _TekkenCharacterListScreenState extends State<TekkenCharacterListScreen> {
  late Future<List<TekkenCharacter>> _characters;

  @override
  void initState() {
    super.initState();
    _characters = WpApiService().fetchTekkenCharacters(perPage: 10, page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TekkenCharacter>>(
      future: _characters,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final characters = snapshot.data ?? [];
        if (characters.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Center(child: Text('No characters found.')),
            ],
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(8.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8.0,
            mainAxisSpacing: 8.0,
          ),
          itemCount: characters.length,
          itemBuilder: (context, index) {
            final c = characters[index];
            return Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.network(c.imageUrl, height: 100, width: 100),
                  Text(c.name),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
