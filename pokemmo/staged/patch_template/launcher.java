package org.pokemmo;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public class Launcher {{

  public static void main(String[] args) throws Exception {{
    System.out.println("---- POKEMMO LAUNCHER ----");

    // Read credentials from file
    String gamedir = System.getenv("GAMEDIR");
    String username = "";
    String password = "";

    if (gamedir != null) {{
      try (BufferedReader reader = new BufferedReader(new FileReader(gamedir + "/credentials.txt"))) {{
        String line = reader.readLine();
        if (line != null) username = line;
        line = reader.readLine();
        if (line != null) password = line;
      }} catch (IOException e) {{
        System.out.println("Could not read credentials.txt: " + e.getMessage());
      }}
    }}

    // Inject credentials into the game's credential class via reflection
    // (avoids replacing the entire class which breaks other methods)
    try {{
      Class<?> credClass = Class.forName("f.{class_name}");

      Field uField = credClass.getDeclaredField("{username}");
      uField.setAccessible(true);
      uField.set(null, username);

      Field pField = credClass.getDeclaredField("{password}");
      pField.setAccessible(true);
      pField.set(null, password);

      System.out.println("Credentials injected successfully");
    }} catch (Exception e) {{
      System.out.println("Failed to inject credentials: " + e.getMessage());
      e.printStackTrace();
    }}

    // Launch the real PokeMMO client
    Class<?> clientClass = Class.forName("com.pokeemu.client.Client");
    Method mainMethod = clientClass.getMethod("main", String[].class);
    mainMethod.invoke(null, (Object) args);
  }}
}}
