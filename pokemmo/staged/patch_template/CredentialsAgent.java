package patch;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;

public class CredentialsAgent {{

  private static String storedUser = "";
  private static String storedPass = "";
  
  public static void premain(String agentArgs, Instrumentation inst) {{
    System.out.println("==== CredentialsAgent premain started ====");
    String gameDir = System.getenv("GAMEDIR");
    System.out.println("GAMEDIR=" + gameDir);
    
    if (gameDir == null || gameDir.isEmpty()) {{
      System.err.println("ERROR: CredentialsAgent - GAMEDIR not set; skipping.");
      return;
    }}

    try (BufferedReader reader = new BufferedReader(new FileReader(gameDir + "/credentials.txt"))) {{
      storedUser = reader.readLine();
      storedPass = reader.readLine();
      if (storedUser == null) storedUser = "";
      if (storedPass == null) storedPass = "";
      System.out.println("CredentialsAgent: Read credentials (user=" + storedUser.length() + " chars)");
    }} catch (IOException e) {{
      System.err.println("ERROR: CredentialsAgent - Failed to read credentials.txt:");
      e.printStackTrace();
      return;
    }}

    // Add a transformer that intercepts the credentials class
    inst.addTransformer(new ClassFileTransformer() {{
      @Override
      public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
                            ProtectionDomain protectionDomain, byte[] classfileBuffer) {{
        if ("f/{class_name}".equals(className)) {{
          System.out.println("CredentialsAgent: Intercepted loading of credentials class");
          // Don't modify bytecode - instead, schedule field injection after class loads
          new Thread(() -> {{
            try {{
              Thread.sleep(100); // Let class finish loading
              Class<?> clazz = Class.forName("f.{class_name}");
              System.out.println("CredentialsAgent: Injecting credentials via thread...");
              setStatic(clazz, "{username}", storedUser);
              setStatic(clazz, "{password}", storedPass);
              setStatic(clazz, "{auto}", Boolean.FALSE);
              System.out.println("CredentialsAgent: Set auto=false to prevent auto-login");
              
              // Keep refreshing every 500ms for the first 10 seconds
              for (int i = 0; i < 20; i++) {{
                Thread.sleep(500);
                Object currentUser = getStatic(clazz, "{username}");
                Object currentPass = getStatic(clazz, "{password}");
                if (currentUser == null || currentUser.toString().isEmpty() ||
                    currentPass == null || currentPass.toString().isEmpty()) {{
                  System.out.println("CredentialsAgent: Re-injecting credentials (attempt " + (i+2) + ")");
                  setStatic(clazz, "{username}", storedUser);
                  setStatic(clazz, "{password}", storedPass);
                  setStatic(clazz, "{auto}", Boolean.FALSE);
                }} else {{
                  System.out.println("CredentialsAgent: Credentials stable at attempt " + (i+2));
                  break;
                }}
              }}
              System.out.println("==== CredentialsAgent monitoring complete ====");
            }} catch (Exception e) {{
              e.printStackTrace();
            }}
          }}).start();
        }}
        return null; // Don't modify bytecode
      }}
    }});
    
    System.out.println("==== CredentialsAgent transformer registered ====");
  }}

  
  private static void setStatic(Class<?> clazz, String fieldName, Object value) throws Exception {{
    java.lang.reflect.Field field = clazz.getDeclaredField(fieldName);
    field.setAccessible(true);
    field.set(null, value);
  }}
  
  private static Object getStatic(Class<?> clazz, String fieldName) throws Exception {{
    java.lang.reflect.Field field = clazz.getDeclaredField(fieldName);
    field.setAccessible(true);
    return field.get(null);
  }}
}}
